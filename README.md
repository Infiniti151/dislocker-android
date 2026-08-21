# dislocker-android

[![Build](https://img.shields.io/github/actions/workflow/status/Infiniti151/dislocker-android/build.yml?branch=dev\&style=for-the-badge\&logo=github-actions\&logoColor=white\&label=Build)](https://github.com/Infiniti151/dislocker-android/actions/workflows/build.yml) [![Android](https://img.shields.io/badge/Android-9%E2%80%9317-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/Infiniti151/dislocker-android) [![License](https://img.shields.io/github/license/Infiniti151/dislocker-android?style=for-the-badge&logo=spdx&logoColor=white&color=yellow&label=License)](https://github.com/Infiniti151/dislocker-android/blob/main/License.md)

[Dislocker](https://github.com/Aorimn/dislocker) is a tool for accessing BitLocker-encrypted volumes on Linux and other Unix-like systems. This project provides Dislocker cross-compiled for Android ARM64 and packaged for [Termux](https://termux.dev/).

The package provides the Dislocker command-line utilities, including `dislocker`, `dislocker-fuse`, `dislocker-file`, `dislocker-metadata`, `dislocker-bek`, `fusermount3` along with the Dislocker and FUSE 3 shared libraries required at runtime.

It was created because Dislocker is not currently available as a package in the official Termux repositories. This project provides a convenient way to install and update Dislocker through a dedicated APT repository for Termux.

## Requirements

* Android device with an **ARM64 (`aarch64`)** CPU
* [Termux](https://termux.dev/)
* Root access
* A BitLocker-encrypted volume
* The appropriate BitLocker recovery password, recovery key, or BEK file

> [!note]
> This package is intended for rooted Android devices running Termux. Dislocker uses FUSE to expose the decrypted BitLocker filesystem. Root access is required to access BitLocker block devices and mount the resulting filesystem.

## Installation

### 1. Install Termux

Install Termux from [F-Droid](https://f-droid.org/packages/com.termux/) or the official Termux project.

Do not mix Termux packages from different sources. In particular, Termux and its add-ons should come from the same distribution source.

**Open Termux and update the package repositories:**

```bash
pkg update
pkg upgrade
```

### 2. Import the repository signing key

The repository is signed using an OpenPGP key published through the Ubuntu keyserver.

**Retrieve the public key using its full fingerprint:**

```bash
gpg --keyserver keyserver.ubuntu.com \
    --recv-keys 77E6A5281DF5538DB12A98F2B31498758A8AF8A5
```

**Verify that the imported key has the expected fingerprint:**

```bash
gpg --fingerprint 77E6A5281DF5538DB12A98F2B31498758A8AF8A5
```

***The fingerprint should be:***

```text
77E6 A528 1DF5 538D B12A 98F2 B314 9875 8A8A F8A5
```

> [!important]
> Verify the fingerprint before trusting the key. It should match the fingerprint published by the repository maintainer.

**Export the verified key as an APT keyring:**

```bash
mkdir -p "$PREFIX/etc/apt/keyrings"

gpg --export 77E6A5281DF5538DB12A98F2B31498758A8AF8A5 \
    > "$PREFIX/etc/apt/keyrings/dislocker-android.gpg"
```

### 3. Add the dislocker APT repository

**Add the repository to your Termux APT sources:**

```bash
echo "deb [signed-by=$PREFIX/etc/apt/keyrings/dislocker-android.gpg] https://Infiniti151.github.io/dislocker-android stable main" \
    > "$PREFIX/etc/apt/sources.list.d/dislocker.list"
```

**Update the package lists:**

```bash
pkg update
```

### 4. Install `dislocker`

**Install with:**

```bash
pkg install dislocker
```

**Verify the installation:**

```bash
dislocker --version
```

You should see the installed Dislocker version.

## Usage

Dislocker does not directly mount a BitLocker volume as a normal
filesystem. It provides two ways to access the decrypted volume:

- `dislocker-fuse` exposes the decrypted volume through FUSE.
- `dislocker-file` exposes the decrypted volume as a flat file, which can then be mounted using the appropriate filesystem driver.

> [!note]
> `dislocker` is the default FUSE-based interface and is provided as a symlink to `dislocker-fuse`. Therefore, running `dislocker` is equivalent to running `dislocker-fuse`.

A typical workflow is:

```text
                    BitLocker volume
                           │
                           ▼
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
       dislocker                  dislocker-file
       (→ dislocker-fuse)                │
              │                          │
              ▼                          ▼
          FUSE mount             decrypted volume file
              │                          │
              ▼                          ▼
     /path/to/mount             filesystem driver
                                         │
                                         ▼
                                  /path/to/mount
```

### 1. Identify the encrypted volume

First identify the block device containing the BitLocker volume.

With root access:

```bash
su
lsblk
```

Depending on your Android device, storage may appear under paths such as:

```text
/dev/block/sd[a-z][1-9]...
```

Do **not** assume a device path. Verify the correct block device before proceeding.

> [!note]
> On many GPT-partitioned Windows drives, the BitLocker volume is the **second partition**. The first partition is often a small 16 MiB Microsoft Reserved (MSR) partition and is **not** the BitLocker volume.
> For example:
>
> ```text
> /dev/block/sda1    16 MiB       Microsoft Reserved (MSR)
> /dev/block/sda2    remaining    BitLocker-encrypted Windows volume
> ```
>
> In this case, use `/dev/block/sda2` with Dislocker. Partition layouts can vary, so always verify the partition containing the BitLocker volume before running Dislocker.

### 2. Create directories

For example:

```bash
su -c "mkdir -p /data/local/tmp/dislocker /mnt/media_rw/dislocker"
```

The first directory will contain the **`dislocker-file` output**, which is the decrypted virtual block device exposed by Dislocker.

The second directory will be the location where the decrypted filesystem is mounted.

### 3. Unlock BitLocker Volume

**Using BitLocker password:**

```bash
su -c "dislocker -V /dev/block/DEVICE -u"YOUR_PASSWORD" -- /data/local/tmp/dislocker"
```

Replace:

```text
/dev/block/DEVICE
```

with the correct BitLocker block device.

For example:

```bash
su -c "dislocker -V /dev/block/sda1 -u"MyPassword" -- /data/local/tmp/dislocker"
```

After successful decryption, Dislocker should create:

```text
/data/local/tmp/dislocker/dislocker-file
```

> [!warning]
> Passing a password directly on the command line can expose it through shell history or process information. Avoid doing this when possible.

**Using BitLocker recovery key:**

A BitLocker recovery key is a unique 48-digit numerical password.

Use:

```bash
su -c "dislocker -V /dev/block/DEVICE -p"YOUR_RECOVERY_KEY" -- /data/local/tmp/dislocker"
```

For example:

```bash
su -c "dislocker -V /dev/block/sda1 -p"111111-222222-333333-444444-555555-666666-777777-888888" -- /data/local/tmp/dislocker"
```

**Using a BEK file:**

If you have a BitLocker external key file (`.bek`), Dislocker can use it with:

```bash
su -c "dislocker -V /dev/block/DEVICE -f /path/to/recovery.bek -- /data/local/tmp/dislocker"
```

### 4. Mount the decrypted filesystem

Once Dislocker has successfully created `dislocker-file`, mount it with FUSE.

**NTFS (requires `ntfs-3g` package):**
```bash
su -M -c "ntfs-3g /data/local/tmp/dislocker/dislocker-file /mnt/media_rw/dislocker"
```

**ExFAT:**

```bash
su -M -c "mount -t exfat -o loop /data/local/tmp/dislocker/dislocker-file /mnt/media_rw/dislocker"
```

**FAT32:**
```bash
su -M -c "mount -t vfat -o loop /data/local/tmp/dislocker/dislocker-file /mnt/media_rw/dislocker"
```

The -M option is provided by the root solution and runs the command in the
global mount namespace, allowing the resulting mount to be visible to other
processes and applications that share that namespace. This makes the mounted folder accessible to root file explorers like SolidExplorer and File Manager+.

> [!important]
> `su -M` is not a standard Android or Linux `su` option. It is provided by Android root solutions, including KernelSU and Magisk. If your root solution does not support `su -M`, the mount may remain isolated to the Termux namespace.

The filesystem type depends on the filesystem contained inside the BitLocker volume.

You can identify the filesystem with:

```bash
file "/data/local/tmp/dislocker/dislocker-file"
```

or, with root:

```bash
su -c "blkid /data/local/tmp/dislocker/dislocker-file"
```

### 6. Unmounting

Unmount the filesystem first:

```bash
su -c "umount /mnt/media_rw/dislocker"
```

Then remove the Dislocker FUSE mount:

```bash
su -c "fusermount3 -u /data/local/tmp/dislocker"
```

## Checking Dislocker options

For the complete list of supported options:

```bash
dislocker --help
```

You can also check the installed version:

```bash
dislocker --version
```

## Android / Termux considerations

### Root access

Accessing a physical block device normally requires root privileges on Android.

You can enter a root shell with:

```bash
su
```

or run individual commands as root:

```bash
su -c "command"
```

Running Dislocker itself as root is generally the simplest approach when accessing Android block devices.

### FUSE

Dislocker relies on FUSE to expose the decrypted BitLocker filesystem.

Your Android kernel and root environment must provide working FUSE support.

Check whether FUSE is available:

```bash
ls -l /dev/fuse
```

If `/dev/fuse` is unavailable, Dislocker cannot provide its normal FUSE-based output. You'll need to use `dislocker-file` to mount the volume as a flat file.

```bash
su -c "dislocker-file -V /dev/block/sda1 -u'uMyPassword' /data/local/tmp/dislocker-file"
```

> [!warning]
> The non-FUSE `dislocker-file` method requires free storage approximately
> equal to the size of the BitLocker volume because the decrypted volume is
> represented as a regular file. The normal FUSE-based method does not require
> this additional storage.

### Storage permissions

Android's normal storage permissions are separate from Linux root permissions.

For access to shared storage, Termux may need storage permission:

```bash
termux-setup-storage
```

This creates:

```text
$HOME/storage/
```

with links to accessible Android shared-storage locations.

For block devices, however, root permissions are normally required.

## Update

**Update all Termux packages:**

```bash
pkg update
pkg upgrade
```

or:

**Upgrade `dislocker`:**

```bash
pkg upgrade dislocker
```

## Uninstallation

**Uninstall `dislocker`:**

```bash
pkg uninstall dislocker
```

**Remove the repository:**

```bash
rm "$PREFIX/etc/apt/sources.list.d/dislocker.list"
```

**Remove the repository signing key:**

```bash
rm "$PREFIX/etc/apt/keyrings/dislocker-android.gpg"
```

**Update**:

```bash
pkg update
```

## Building

This repository builds Dislocker for Android ARM64 using the Android NDK.

The GitHub Actions workflow:

1. Builds libfuse 3.x for Android ARM64.
2. Builds mbedTLS 3.x for Android ARM64.
3. Builds Dislocker against the Android libraries.
4. Packages the resulting binaries and libraries into a Termux-compatible `.deb`.
5. Generates an APT repository.
6. Generates `Packages` and `Packages.gz`.
7. Generates and signs the `Release` metadata.
8. Generates a signed `InRelease`.
9. Publishes the repository using GitHub Pages.

The resulting repository is structured as:

```text
apt-repo/
├── dists/
│   └── stable/
│       ├── InRelease
│       ├── Release
│       ├── Release.gpg
│       └── main/
│           └── binary-aarch64/
│               ├── Packages
│               └── Packages.gz
└── pool/
    └── main/
        └── d/
            └── dislocker/
                └── dislocker_*.deb
```

## Source

This project packages [Dislocker](https://github.com/Aorimn/dislocker) for Android ARM64.

Original Dislocker project:

https://github.com/Aorimn/dislocker

## License

See the original [Dislocker](https://github.com/Aorimn/dislocker) project for its licensing information.

The Android build and packaging files in this repository are provided separately from the upstream Dislocker source.

