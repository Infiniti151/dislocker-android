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
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
API="${API:-28}"
GENERATE_APT_REPO="${GENERATE_APT_REPO:-true}"

echo -e "${CYAN}=== [1/5] Staging NDK $NDK_VERSION to native container storage (/opt) ===${NC}"
mkdir -p "$WORK_DIR" "$INSTALL_DIR/lib" "$CACHE_DIR"

# --- Download NDK if not cached ---
if [ ! -d "$NDK_SRC" ]; then
    echo -e "${YELLOW}Downloading Android NDK ($NDK_VERSION)...${NC}"
    wget -q --show-progress \
      "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip" \
      -O "$CACHE_DIR/ndk.zip"
    unzip -q "$CACHE_DIR/ndk.zip" -d "$CACHE_DIR"
    rm -f "$CACHE_DIR/ndk.zip"
fi

# --- Copy NDK into /opt ---
if [ ! -d "$NDK" ]; then
    echo -e "${YELLOW}Copying NDK from cache volume to /opt...${NC}"
    cp -a "$NDK_SRC" /opt/
fi

echo -e "${YELLOW}Granting execution permissions to toolchain binaries...${NC}"
chmod -R +x "$TOOLCHAIN/bin/"

# Validate that clang can actually execute on this filesystem
if ! "$TOOLCHAIN/bin/clang" --version > /dev/null 2>&1; then
    echo -e "${RED}Error: Clang binary is not executable. Check file attributes:${NC}"
    file "$TOOLCHAIN/bin/clang" || true
    exit 1
fi

echo -e "${YELLOW}NDK environment validated successfully in /opt.${NC}\n"

echo -e "${CYAN}=== [2/5] Cross-Compiling mbedTLS 3.x for Android ARM64 ===${NC}"
cd "$WORK_DIR"

# Dynamically fetch remote tags, filter for semantic v3.x.x tags, sort, and select the latest
echo -e "${YELLOW}Detecting latest mbedTLS v3 release tag...${NC}"

LATEST_V3_TAG=$(git ls-remote --tags https://github.com/Mbed-TLS/mbedtls.git \
  | grep -o 'refs/tags/v3\.[0-9.]*' \
  | cut -d/ -f3 \
  | sort -V \
  | tail -n1)

# Fallback safeguard in case git network lookup fails
if [ -z "$LATEST_V3_TAG" ]; then
    echo -e "${YELLOW}Warning: Could not auto-detect remote tags. Falling back to v3.6.0.${NC}"
    LATEST_V3_TAG="v3.6.0"
fi

echo -e "${YELLOW}Selected mbedTLS Tag: ${LATEST_V3_TAG}${NC}"

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

rm -rf build && mkdir -p build && cd build

echo -e "\n${YELLOW}=== Compiling MbedTLS ===${NC}"
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=$API \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DENABLE_PROGRAMS=OFF \
  -DENABLE_TESTING=OFF

cmake --build . --parallel
cmake --install .

echo -e "\n${CYAN}=== [3/5] Cross-Compiling Dislocker ===${NC}"
cd "$WORK_DIR"
if [ ! -d "dislocker" ]; then
    git clone https://github.com/Aorimn/dislocker.git
fi
cd dislocker

DISLOCKER_COMMIT="$(git rev-parse HEAD)"
DISLOCKER_SHORT_COMMIT="$(git rev-parse --short HEAD)"
DISLOCKER_DATE="$(git show -s --format=%cd --date=format:%Y%m%d "$DISLOCKER_COMMIT")"

DISLOCKER_VERSION="0.0~git${DISLOCKER_DATE}.${DISLOCKER_SHORT_COMMIT}"

# CMake expects platform-specific man pages under man/<platform>/.
# Upstream provides Linux man pages but no Android-specific set,
# so use the Linux pages to satisfy the Android build.
# These are build-time files and are not packaged for Termux.
mkdir -p man/android
cp man/linux/*.1 man/android/

# Android Bionic handles pthreads natively within libc.
# We create stub linker script to safely absorb the `-lpthread` flag.
echo 'INPUT(-lc)' > "$INSTALL_DIR/lib/libpthread.so"

# Automatically locate MbedTLS CMake configuration directory
MBEDTLS_DIR_PATH=$(dirname "$(find "$INSTALL_DIR" -name "MbedTLSConfig.cmake" | head -n 1)")

# ---------------------------------------------------------------------------
# Configure Termux FUSE 3
# ---------------------------------------------------------------------------

TERMUX_FUSE3_ROOT="/opt/termux-fuse3"
TERMUX_FUSE3_PREFIX="$TERMUX_FUSE3_ROOT/data/data/com.termux/files/usr"

export PKG_CONFIG_SYSROOT_DIR="$TERMUX_FUSE3_ROOT"
export PKG_CONFIG_LIBDIR="$TERMUX_FUSE3_PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$TERMUX_FUSE3_PREFIX/lib/pkgconfig"

export CMAKE_PREFIX_PATH="$INSTALL_DIR"

echo -e "\n${YELLOW}=== Termux FUSE 3 configuration ===${NC}"

echo "FUSE3 prefix: $TERMUX_FUSE3_PREFIX"
echo "FUSE3 pkgconfig: $TERMUX_FUSE3_PREFIX/lib/pkgconfig"
echo "FUSE3 version: $(pkg-config --modversion fuse3)"
echo "FUSE3 cflags: $(pkg-config --cflags fuse3)"
echo "FUSE3 libs: $(pkg-config --libs fuse3)"

rm -rf build && mkdir -p build && cd build

echo -e "\n${YELLOW}=== Compiling Dislocker ===${NC}"
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=$API \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DCMAKE_EXE_LINKER_FLAGS="-L$INSTALL_DIR/lib" \
  -DCMAKE_SHARED_LINKER_FLAGS="-L$INSTALL_DIR/lib" \
  -DMbedTLS_DIR="$MBEDTLS_DIR_PATH"

cmake --build . --parallel
cmake --install .

echo -e "\n${YELLOW}=== Verifying FUSE linkage ===${NC}"

readelf -d "$INSTALL_DIR/bin/dislocker" | grep NEEDED

echo -e "\n${YELLOW}=== Verifying FUSE library ===${NC}"

ls -l "$TERMUX_FUSE3_PREFIX/lib/libfuse3.so"

if [ "$GENERATE_APT_REPO" = "false" ]; then
    echo -e "\n${GREEN}=== Skipping APT repository generation and signing (local build) ===${NC}"
    exit 0
fi

echo -e "${CYAN}=== [4/5] Generating APT Repository ===${NC}"

TERMUX_PREFIX="/data/data/com.termux/files/usr"
PKG_STAGE="$WORK_DIR/pkg-staging"

APT_REPO_DIR="$WORK_DIR/output/apt-repo"
REPO_NAME="dislocker-android"

DIST="stable"
COMPONENT="main"
ARCH="aarch64"

APT_DIST_DIR="$APT_REPO_DIR/dists/$DIST"
APT_BINARY_DIR="$APT_DIST_DIR/$COMPONENT/binary-$ARCH"
APT_POOL_DIR="$APT_REPO_DIR/pool/$COMPONENT/d/dislocker"

echo -e "\n${YELLOW}Package version: $DISLOCKER_VERSION${NC}"

# ---------------------------------------------------------------------------
# Clean previous package/repository output
# ---------------------------------------------------------------------------

echo -e "\n${YELLOW}=== Preparing package and APT repository directories ===${NC}"

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

echo -e "\n${YELLOW}=== Copying binaries ===${NC}"

cp -a \
    "$INSTALL_DIR/bin"/dislocker* \
    "$PKG_STAGE/$TERMUX_PREFIX/bin/"

# ---------------------------------------------------------------------------
# Copy libraries
# ---------------------------------------------------------------------------

echo -e "\n${YELLOW}=== Copying libraries ===${NC}"

cp -a \
    "$INSTALL_DIR/lib/libdislocker.so"* \
    "$PKG_STAGE/$TERMUX_PREFIX/lib/"

# ---------------------------------------------------------------------------
# Permissions
# ---------------------------------------------------------------------------

echo -e "\n${YELLOW}=== Setting permissions ===${NC}"

chmod 755 \
    "$PKG_STAGE/$TERMUX_PREFIX/bin/"*

chmod 644 \
    "$PKG_STAGE/$TERMUX_PREFIX/lib/"*

# ---------------------------------------------------------------------------
# Debian control file
# ---------------------------------------------------------------------------

echo -e "\n${YELLOW}=== Creating package control file ===${NC}"

INSTALLED_SIZE="$(du -sk --apparent-size "$PKG_STAGE" | cut -f1)"

cat > "$PKG_STAGE/DEBIAN/control" <<EOF
Package: dislocker
Version: $DISLOCKER_VERSION
Architecture: $ARCH
Maintainer: Infiniti151
Installed-Size: $INSTALLED_SIZE
Depends: libfuse3
Section: utils
Priority: optional
Homepage: https://github.com/Aorimn/dislocker
Description: FUSE-based BitLocker driver for Termux Android ARM64
 Cross-compiled for Android ARM64 using the Android NDK.
EOF

# ---------------------------------------------------------------------------
# Build .deb
# ---------------------------------------------------------------------------

echo -e "\n${YELLOW}=== Building .deb ===${NC}"

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

echo -e "\n${YELLOW}=== Generating Packages index ===${NC}"

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

echo -e "\n${YELLOW}=== Generating Release file ===${NC}"

cat > "$WORK_DIR/apt-release.conf" <<EOF
APT::FTPArchive::Release::Origin "$REPO_NAME";
APT::FTPArchive::Release::Label "$REPO_NAME";
APT::FTPArchive::Release::Suite "$DIST";
APT::FTPArchive::Release::Codename "$DIST";
APT::FTPArchive::Release::Architectures "$ARCH";
APT::FTPArchive::Release::Components "$COMPONENT";
APT::FTPArchive::Release::Description "Dislocker APT repository for Termux Android ARM64";
EOF

apt-ftparchive \
    -c "$WORK_DIR/apt-release.conf" \
    release \
    "$APT_DIST_DIR" \
    > "$APT_DIST_DIR/Release"

echo -e "\n${YELLOW}=== Release file ===${NC}"
cat "$APT_DIST_DIR/Release"

echo
echo -e "\n${YELLOW}=== APT repository tree ===${NC}"
find "$APT_REPO_DIR" -type f -print | sort

echo
echo -e "\n${YELLOW}=== Packages index ===${NC}"
cat "$APT_BINARY_DIR/Packages"

echo -e "\n${CYAN}=== [5/5] Signing APT repository ===${NC}"

if [ -z "${GPG_KEY:-}" ]; then
    echo -e "${RED}Error: GPG_KEY is not set.${NC}"
    exit 1
fi

if [ -z "${GPG_PASSPHRASE:-}" ]; then
    echo -e "${RED}Error: GPG_PASSPHRASE is not set.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}=== Available signing keys ===${NC}"
gpg --batch --list-secret-keys

echo -e "\n${YELLOW}=== Signing Release file ===${NC}"

gpg --batch --yes \
    --pinentry-mode loopback \
    --passphrase "$GPG_PASSPHRASE" \
    --local-user "$GPG_KEY" \
    --armor \
    --detach-sign \
    --output "$APT_DIST_DIR/Release.gpg" \
    "$APT_DIST_DIR/Release"

echo -e "\n${YELLOW}=== Creating InRelease ===${NC}"

gpg --batch --yes \
    --pinentry-mode loopback \
    --passphrase "$GPG_PASSPHRASE" \
    --local-user "$GPG_KEY" \
    --clearsign \
    --output "$APT_DIST_DIR/InRelease" \
    "$APT_DIST_DIR/Release"

echo -e "\n${YELLOW}=== Verifying Release.gpg ===${NC}"

gpg --batch --verify \
    "$APT_DIST_DIR/Release.gpg" \
    "$APT_DIST_DIR/Release"

echo -e "\n${YELLOW}=== Verifying InRelease ===${NC}"

gpg --batch --verify \
    "$APT_DIST_DIR/InRelease"

echo -e "${GREEN}
====================================================
Build complete!

Signed APT repository generated at:
$APT_REPO_DIR
====================================================
${NC}"