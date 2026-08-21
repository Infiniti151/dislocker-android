#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Infiniti151

set -euo pipefail

# --- Color codes ---
CYAN='\033[36m'
YELLOW='\033[33m'
GREEN='\033[32m'
NC='\033[0m'

# --- Configuration ---
WORK_DIR="${GITHUB_WORKSPACE:-/workspace}"
INSTALL_DIR="$WORK_DIR/output"
CACHE_DIR="$WORK_DIR/cache"
NDK_VERSION="r29"
NDK_SRC="$CACHE_DIR/android-ndk-$NDK_VERSION"
NDK="/opt/android-ndk-$NDK_VERSION"
API="${API:-28}"
TARGET="aarch64-linux-android"

echo -e "${CYAN}=== [1/4] Staging NDK $NDK_VERSION to native container storage (/opt) ===${NC}"
mkdir -p "$WORK_DIR" "$INSTALL_DIR/lib" "$CACHE_DIR"

# Android Bionic handles pthreads natively within libc.
# We create stub linker scripts to safely absorb `-lpthread` and `-lrt` flags.
echo 'INPUT(-lc)' > "$INSTALL_DIR/lib/libpthread.so"
echo 'INPUT(-lc)' > "$INSTALL_DIR/lib/librt.so"

# --- Download NDK if not cached ---
if [ ! -d "$NDK_SRC" ]; then
    echo "Downloading Android NDK ($NDK_VERSION)..."
    wget -q --show-progress \
      "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip" \
      -O "$CACHE_DIR/ndk.zip"
    unzip -q "$CACHE_DIR/ndk.zip" -d "$CACHE_DIR"
    rm -f "$CACHE_DIR/ndk.zip"
fi

# --- Copy NDK into /opt ---
if [ ! -d "$NDK" ]; then
    echo "Copying NDK from cache volume to /opt..."
    cp -a "$NDK_SRC" /opt/
fi

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"

echo "Granting execution permissions to toolchain binaries..."
chmod -R +x "$TOOLCHAIN/bin/"

# Validate that clang can actually execute on this filesystem
if ! "$TOOLCHAIN/bin/clang" --version > /dev/null 2>&1; then
    echo "Error: Clang binary is not executable. Check file attributes:"
    file "$TOOLCHAIN/bin/clang" || true
    exit 1
fi

echo "NDK environment validated successfully in /opt."

# --- Meson cross-file ---
cat << EOF > /tmp/android-cross.txt
[binaries]
c = ['$TOOLCHAIN/bin/clang', '--target=${TARGET}${API}']
cpp = ['$TOOLCHAIN/bin/clang++', '--target=${TARGET}${API}']
ar = '$TOOLCHAIN/bin/llvm-ar'
strip = '$TOOLCHAIN/bin/llvm-strip'
pkgconfig = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

echo -e "${CYAN}=== [2/4] Cross-Compiling libfuse 3.x ===${NC}"
cd "$WORK_DIR"

# Dynamically fetch remote tags, filter for semantic v3.x.x tags, sort, and select the latest
echo "Detecting latest libfuse v3 release tag..."
LATEST_V3_TAG=$(git ls-remote --tags https://github.com/libfuse/libfuse.git \
  | grep -o 'refs/tags/fuse-3\.[0-9.]*' \
  | cut -d/ -f3 \
  | sort -V \
  | tail -n1)

# Fallback safeguard in case git network lookup fails
if [ -z "$LATEST_V3_TAG" ]; then
    echo "Warning: Could not auto-detect remote tags. Falling back to fuse-3.18.2."
    LATEST_V3_TAG="fuse-3.18.2"
fi

echo "Selected libfuse Tag: ${LATEST_V3_TAG}"

# Clone or checkout the specific tag directly
if [ ! -d "libfuse" ]; then
    git clone --depth 1 --branch "$LATEST_V3_TAG" https://github.com/libfuse/libfuse.git
else
    cd libfuse
    git fetch --tags --depth 1 origin tag "$LATEST_V3_TAG"
    git checkout "$LATEST_V3_TAG"
    cd ..
fi

cd libfuse

# 1. Safely remove librt lookup
# 2. Inject pthread cancellation fallbacks for Android into lib/fuse_i.h
# 3. Neutralize install_helper.sh so it exits cleanly without device-node errors
python3 -c "
import os

path_meson = 'lib/meson.build'
if os.path.exists(path_meson):
    with open(path_meson, 'r') as f:
        lines = f.readlines()
    new_lines = [line for line in lines if 'find_library(\\'rt\\'' not in line and \"find_library('rt'\" not in line]
    with open(path_meson, 'w') as f:
        f.writelines(new_lines)

path_header = 'lib/fuse_i.h'
if os.path.exists(path_header):
    with open(path_header, 'r') as f:
        content = f.read()

    stubs = '''
#ifdef __ANDROID__
#ifndef PTHREAD_CANCEL_ENABLE
#define PTHREAD_CANCEL_ENABLE 0
#endif
#ifndef PTHREAD_CANCEL_DISABLE
#define PTHREAD_CANCEL_DISABLE 0
#endif
#ifndef pthread_setcancelstate
#define pthread_setcancelstate(state, oldstate) (0)
#endif
#ifndef pthread_cancel
#define pthread_cancel(thread) (0)
#endif
#endif
'''
    if '__ANDROID__' not in content:
        with open(path_header, 'w') as f:
            f.write(stubs + '\n' + content)

path_script = 'util/install_helper.sh'
if os.path.exists(path_script):
    with open(path_script, 'w') as f:
        f.write('#!/bin/sh\nexit 0\n')
"

rm -rf build-dislocker
meson setup build-dislocker \
  --cross-file /tmp/android-cross.txt \
  --prefix="$INSTALL_DIR" \
  -Dexamples=false \
  -Dtests=false

ninja -C build-dislocker
ninja -C build-dislocker install

echo -e "${CYAN}=== [2/4] Cross-Compiling mbedTLS 3.x for Android ARM64 ===${NC}"
cd "$WORK_DIR"

# Dynamically fetch remote tags, filter for semantic v3.x.x tags, sort, and select the latest
echo "Detecting latest mbedTLS v3 release tag..."
LATEST_V3_TAG=$(git ls-remote --tags https://github.com/Mbed-TLS/mbedtls.git \
  | grep -o 'refs/tags/v3\.[0-9.]*' \
  | cut -d/ -f3 \
  | sort -V \
  | tail -n1)

# Fallback safeguard in case git network lookup fails
if [ -z "$LATEST_V3_TAG" ]; then
    echo "Warning: Could not auto-detect remote tags. Falling back to v3.6.0."
    LATEST_V3_TAG="v3.6.0"
fi

echo "Selected mbedTLS Tag: ${LATEST_V3_TAG}"

# Clone or checkout the specific tag directly
if [ ! -d "mbedtls" ]; then
    git clone --depth 1 --branch "$LATEST_V3_TAG" https://github.com/Mbed-TLS/mbedtls.git
else
    cd mbedtls
    git fetch --tags --depth 1 origin tag "$LATEST_V3_TAG"
    git checkout "$LATEST_V3_TAG"
    cd ..
fi

cd mbedtls
git submodule update --init --recursive

rm -rf build-dislocker && mkdir -p build-dislocker && cd build-dislocker
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=$API \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DENABLE_PROGRAMS=OFF \
  -DENABLE_TESTING=OFF

make -j$(nproc)
make install

echo -e "${CYAN}=== [4/4] Cross-Compiling Dislocker ===${NC}"
cd "$WORK_DIR"
if [ ! -d "dislocker" ]; then
    git clone https://github.com/Aorimn/dislocker.git
fi
cd dislocker

DISLOCKER_COMMIT="$(git rev-parse HEAD)"
DISLOCKER_SHORT_COMMIT="$(git rev-parse --short HEAD)"
DISLOCKER_DATE="$(git show -s --format=%cd --date=format:%Y%m%d "$DISLOCKER_COMMIT")"

DISLOCKER_VERSION="0.0~git${DISLOCKER_DATE}.${DISLOCKER_SHORT_COMMIT}"

# Create man/android target directory and populate/touch man pages to satisfy packaging gzip rules
mkdir -p man/android
for f in man/*.1; do
    if [ -f "$f" ]; then
        cp "$f" man/android/
    fi
done
touch man/android/dislocker.1 man/android/dislocker-file.1 man/android/dislocker-fuse.1 man/android/dislocker-metadata.1 man/android/dislocker-bek.1

export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig:$INSTALL_DIR/lib/aarch64-linux-android/pkgconfig"
export CMAKE_PREFIX_PATH="$INSTALL_DIR"

# Automatically locate MbedTLS CMake configuration directory
MBEDTLS_DIR_PATH=$(dirname "$(find "$INSTALL_DIR" -name "MbedTLSConfig.cmake" | head -n 1)")

rm -rf build && mkdir -p build && cd build
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=$API \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DCMAKE_EXE_LINKER_FLAGS="-L$INSTALL_DIR/lib" \
  -DCMAKE_SHARED_LINKER_FLAGS="-L$INSTALL_DIR/lib" \
  -DMbedTLS_DIR="$MBEDTLS_DIR_PATH" \
  -DUSE_FUSE3=ON

make -j$(nproc)
make install

echo -e "${CYAN}=== [5/6] Generating APT Repository ===${NC}"

TERMUX_PREFIX="/data/data/com.termux/files/usr"
PKG_STAGE="$WORK_DIR/pkg-staging"

APT_REPO_DIR="$WORK_DIR/output/apt-repo"

DIST="stable"
COMPONENT="main"
ARCH="aarch64"

APT_DIST_DIR="$APT_REPO_DIR/dists/$DIST"
APT_BINARY_DIR="$APT_DIST_DIR/$COMPONENT/binary-$ARCH"
APT_POOL_DIR="$APT_REPO_DIR/pool/$COMPONENT/d/dislocker"

echo "Package version: $DISLOCKER_VERSION"

# ---------------------------------------------------------------------------
# Clean previous package/repository output
# ---------------------------------------------------------------------------

rm -rf "$PKG_STAGE"

mkdir -p \
    "$PKG_STAGE/$TERMUX_PREFIX/bin" \
    "$PKG_STAGE/$TERMUX_PREFIX/lib" \
    "$PKG_STAGE/DEBIAN" \
    "$APT_BINARY_DIR" \
    "$APT_POOL_DIR"

# ---------------------------------------------------------------------------
# Copy binaries
# ---------------------------------------------------------------------------

echo -e "${YELLOW}=== [Copying binaries ===${NC}"

cp -f \
    "$INSTALL_DIR/bin/"* \
    "$PKG_STAGE/$TERMUX_PREFIX/bin/"

# ---------------------------------------------------------------------------
# Copy libraries
# ---------------------------------------------------------------------------

echo -e "${YELLOW}=== [Copying libraries ===${NC}"

cp -a \
    "$INSTALL_DIR/lib/libdislocker.so"* \
    "$PKG_STAGE/$TERMUX_PREFIX/lib/"

cp -a \
    "$INSTALL_DIR/lib/libfuse3.so"* \
    "$PKG_STAGE/$TERMUX_PREFIX/lib/"

# ---------------------------------------------------------------------------
# Permissions
# ---------------------------------------------------------------------------

chmod 755 \
    "$PKG_STAGE/$TERMUX_PREFIX/bin/"*

chmod 644 \
    "$PKG_STAGE/$TERMUX_PREFIX/lib/"*

# ---------------------------------------------------------------------------
# Debian control file
# ---------------------------------------------------------------------------

echo -e "${YELLOW}=== [Creating package control file ===${NC}"

INSTALLED_SIZE="$(du -sk --apparent-size "$PKG_STAGE" | cut -f1)"

cat > "$PKG_STAGE/DEBIAN/control" <<EOF
Package: dislocker
Version: $DISLOCKER_VERSION
Architecture: $ARCH
Maintainer: Infiniti151
Installed-Size: $INSTALLED_SIZE
Section: utils
Priority: optional
Homepage: https://github.com/Aorimn/dislocker
Description: FUSE-based BitLocker driver for Termux Android ARM64
 Cross-compiled for Android ARM64 using the Android NDK.
EOF

# ---------------------------------------------------------------------------
# Build .deb
# ---------------------------------------------------------------------------

echo -e "${YELLOW}=== [Building .deb ===${NC}"

DEB_FILE_NAME="dislocker_${DISLOCKER_VERSION}_${ARCH}.deb"
DEB_FILE="$APT_POOL_DIR/$DEB_FILE_NAME"

dpkg-deb \
    --build \
    "$PKG_STAGE" \
    "$DEB_FILE"

echo "Successfully built:"
echo "$DEB_FILE"

echo "DEB_FILE=$DEB_FILE" >> "$GITHUB_ENV"

# ---------------------------------------------------------------------------
# Generate Packages index
# ---------------------------------------------------------------------------

echo -e "${YELLOW}=== [Generating Packages index ===${NC}"

(
    cd "$APT_REPO_DIR"

    dpkg-scanpackages \
        --arch "$ARCH" \
        pool \
        /dev/null \
        > "$APT_BINARY_DIR/Packages"
)

gzip -9 -c \
    "$APT_BINARY_DIR/Packages" \
    > "$APT_BINARY_DIR/Packages.gz"

# ---------------------------------------------------------------------------
# Generate Release metadata
# ---------------------------------------------------------------------------

echo -e "${YELLOW}=== [Generating Release file ===${NC}"

cd "$APT_DIST_DIR"

DATE_RFC2822="$(date -Ru)"

PACKAGES_SIZE="$(stat -c '%s' "$APT_BINARY_DIR/Packages")"
PACKAGES_GZ_SIZE="$(stat -c '%s' "$APT_BINARY_DIR/Packages.gz")"

PACKAGES_MD5="$(
    md5sum "$APT_BINARY_DIR/Packages" |
    awk '{print $1}'
)"

PACKAGES_GZ_MD5="$(
    md5sum "$APT_BINARY_DIR/Packages.gz" |
    awk '{print $1}'
)"

PACKAGES_SHA256="$(
    sha256sum "$APT_BINARY_DIR/Packages" |
    awk '{print $1}'
)"

PACKAGES_GZ_SHA256="$(
    sha256sum "$APT_BINARY_DIR/Packages.gz" |
    awk '{print $1}'
)"

cat > "$APT_DIST_DIR/Release" <<EOF
Origin: dislocker-android
Label: dislocker-android
Suite: $DIST
Codename: $DIST
Date: $DATE_RFC2822
Architectures: $ARCH
Components: $COMPONENT
Description: Dislocker APT repository for Termux Android ARM64

MD5Sum:
 $PACKAGES_MD5 $PACKAGES_SIZE $COMPONENT/binary-$ARCH/Packages
 $PACKAGES_GZ_MD5 $PACKAGES_GZ_SIZE $COMPONENT/binary-$ARCH/Packages.gz

SHA256:
 $PACKAGES_SHA256 $PACKAGES_SIZE $COMPONENT/binary-$ARCH/Packages
 $PACKAGES_GZ_SHA256 $PACKAGES_GZ_SIZE $COMPONENT/binary-$ARCH/Packages.gz
EOF

echo -e "${YELLOW}=== [Release file ===${NC}"
cat "$APT_DIST_DIR/Release"

echo
echo -e "${YELLOW}=== [APT repository tree ===${NC}"
find "$APT_REPO_DIR" -type f -print | sort

echo
echo -e "${YELLOW}=== [Packages index ===${NC}"
cat "$APT_BINARY_DIR/Packages"

echo -e "${CYAN}=== [6/6] Signing APT repository ===${NC}"

if [ -z "${GPG_KEY:-}" ]; then
    echo "ERROR: GPG_KEY is not set"
    exit 1
fi

if [ -z "${GPG_PASSPHRASE:-}" ]; then
    echo "ERROR: GPG_PASSPHRASE is not set"
    exit 1
fi

echo -e "${YELLOW}=== [Available signing keys ===${NC}"
gpg --batch --list-secret-keys

echo -e "${YELLOW}=== [Signing Release file ===${NC}"

gpg --batch --yes \
    --pinentry-mode loopback \
    --passphrase "$GPG_PASSPHRASE" \
    --local-user "$GPG_KEY" \
    --armor \
    --detach-sign \
    --output "$APT_DIST_DIR/Release.gpg" \
    "$APT_DIST_DIR/Release"

echo -e "${YELLOW}=== [Creating InRelease ===${NC}"

gpg --batch --yes \
    --pinentry-mode loopback \
    --passphrase "$GPG_PASSPHRASE" \
    --local-user "$GPG_KEY" \
    --clearsign \
    --output "$APT_DIST_DIR/InRelease" \
    "$APT_DIST_DIR/Release"

echo -e "${YELLOW}=== [Verifying Release.gpg ===${NC}"

gpg --batch --verify \
    "$APT_DIST_DIR/Release.gpg" \
    "$APT_DIST_DIR/Release"

echo -e "${YELLOW}=== [Verifying InRelease ===${NC}"

gpg --batch --verify \
    "$APT_DIST_DIR/InRelease"

echo
echo "${GREEN}===================================================="
echo "Build complete!"
echo "Signed APT repository generated at:"
echo "$APT_REPO_DIR"
echo "====================================================${NC}"