# dislocker-android

[![Build](https://img.shields.io/github/actions/workflow/status/Infiniti151/dislocker-android/build.yml?branch=main\&style=for-the-badge\&logo=github-actions\&logoColor=white\&label=Build)](https://github.com/Infiniti151/dislocker-android/actions/workflows/build.yml) [![Android](https://img.shields.io/badge/Android-9%E2%80%9317-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/Infiniti151/dislocker-android) [![License](https://img.shields.io/github/license/Infiniti151/dislocker-android?style=for-the-badge&logo=spdx&logoColor=white&color=yellow&label=License)](https://github.com/Infiniti151/dislocker-android/blob/main/LICENSE)

[Dislocker](https://github.com/Aorimn/dislocker) is a tool for accessing BitLocker-encrypted volumes on Linux and other Unix-like systems. This project provides Dislocker cross-compiled for Android ARM64 and packaged for [Termux](https://termux.dev/).

The package provides the Dislocker command-line utilities and uses the existing Termux FUSE 3 userspace tools provided by the `libfuse3` package.

It was created because Dislocker is not currently available as a package in the official Termux repositories. This project provides a convenient way to install and update Dislocker through a dedicated APT repository for Termux.

## 📋 Requirements

* Android device with an **ARM64 (`aarch64`)** CPU
* [Termux](https://termux.dev/)
* Root access
* A BitLocker-encrypted volume
* The appropriate BitLocker password, recovery key, or BEK file

## 📦 Installation

### 1. Install Termux

Install Termux from [F-Droid](https://f-droid.org/packages/com.termux/) or another official Termux distribution source.

> [!important]
> Do not mix Termux packages or add-ons from different distribution sources. Termux and its add-ons should come from the same source.

### 2. Update Termux packages

Open Termux and update the package repositories:

```bash
pkg update
pkg upgrade
```

### 3. Import the repository signing key

The repository is signed using an OpenPGP key published through the Ubuntu keyserver.

**Install `gnupg` (if not installed):**:
```bash
pkg install gnupg
```

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

### 4. Add the dislocker APT repository

**Add the repository to your Termux APT sources:**

```bash
echo "deb [signed-by=$PREFIX/etc/apt/keyrings/dislocker-android.gpg] https://Infiniti151.github.io/dislocker-android stable main" \
    > "$PREFIX/etc/apt/sources.list.d/dislocker.list"
```

**Update the package lists:**

```bash
pkg update
```

### 5. Install `dislocker`

**Install with:**

```bash
pkg install dislocker
```

**Verify the installation:**

```bash
dislocker --version
```

You should see the installed Dislocker version.

## 🔧 Usage

Dislocker does not directly mount a BitLocker volume as a normal filesystem. It provides two ways to access the decrypted volume:

* `dislocker-fuse` exposes the decrypted volume through FUSE.
* `dislocker-file` exposes the decrypted volume as a flat file, which can then be mounted using the appropriate filesystem driver.

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

### Global vs. Termux-only access

On Android, mount namespaces determine which processes can see filesystems and FUSE mounts.

Choose **one of the following workflows** depending on where you intend to access the decrypted volume:

* **Termux-only:** Use `tsu` for the entire Dislocker workflow. The decrypted volume remains accessible from Termux but is isolated from Android applications and file managers.
* **Global / Android access:** Use `gsu` for the entire Dislocker workflow. This runs commands in the **global mount namespace**, allowing the resulting decrypted volume and filesystem mount to be accessed by Android processes that share that namespace, including compatible root-capable file managers.

`gsu` is a small helper function that runs commands using the Termux environment with root privileges in the **global mount namespace**:

```bash
gsu() {
    /system/bin/su -M -c \
        'export PATH=/data/data/com.termux/files/usr/bin:$PATH
         export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib:$LD_LIBRARY_PATH
         "$@"' \
        sh "$@"
}
```

Add this function to your shell configuration (for example, `~/.bashrc` or `~/.config/fish/config.fish`, depending on your shell) to make it available in future sessions.

> [!important]
> `gsu` is a convenience function provided by this documentation; it is not a standard Android or Termux command.

> [!note]
> The `-M` (`--mount-master`) option is provided by KernelSU and some other Android root solutions. It runs the command in the global mount namespace, allowing mounts created by the command to be visible to other processes that share that namespace.

> [!warning]
> Do not mix `tsu` and `gsu` within the same Dislocker workflow when using the global workflow. In particular, run Dislocker and the subsequent filesystem mount with `gsu` so that they operate in the same mount namespace.

### 1. Identify the encrypted volume

First identify the block device containing the BitLocker volume with `lsblk` (requires `blk-utils` package).

For example:

```bash
tsu
lsblk
```

Depending on your Android device, storage may appear under paths such as:

```text
/dev/block/sd[a-z][1-9]...
```

**Do not assume a device path.** Verify the correct block device before proceeding.

> [!note]
> On many GPT-partitioned Windows drives, the BitLocker volume is the **second partition**. The first partition is often a small 16 MiB Microsoft Reserved (MSR) partition and is **not** the BitLocker volume.
>
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
gsu mkdir -p /data/local/tmp/dislocker /mnt/media_rw/bitlocker
```

The first directory will contain the **`dislocker-file` output**, which is the decrypted virtual block device exposed by Dislocker.

The second directory will be the location where the decrypted filesystem is mounted.

### 3. Unlock BitLocker Volume

#### **Using BitLocker password:**

```bash
gsu dislocker -V /dev/block/DEVICE -u"YOUR_PASSWORD" -- /data/local/tmp/dislocker
```

Replace:

```text
/dev/block/DEVICE
```

with the correct BitLocker block device.

For example:

```bash
gsu dislocker -V /dev/block/sda2 -u"MyPassword" -- /data/local/tmp/dislocker
```

After successful decryption, Dislocker should create:

```text
/data/local/tmp/dislocker/dislocker-file
```

> [!warning]
> Passing a password directly on the command line can expose it through shell history or process information. Avoid doing this when possible.

#### **Using BitLocker recovery key:**

A BitLocker recovery key is a unique 48-digit numerical password.

Use:

```bash
gsu dislocker -V /dev/block/DEVICE -p"YOUR_RECOVERY_KEY" -- /data/local/tmp/dislocker
```

For example:

```bash
gsu dislocker -V /dev/block/sda2 -p"111111-222222-333333-444444-555555-666666-777777-888888" -- /data/local/tmp/dislocker
```

#### **Using a BEK file:**

If you have a BitLocker external key file (`.bek`), Dislocker can use it with:

```bash
gsu dislocker -V /dev/block/DEVICE -f /path/to/recovery.bek -- /data/local/tmp/dislocker
```

### 4. Mount the decrypted filesystem

Once Dislocker has successfully created `dislocker-file`, mount it with the appropriate filesystem driver.

#### **NTFS (requires `ntfs-3g` package):**

```bash
gsu ntfs-3g /data/local/tmp/dislocker/dislocker-file /mnt/media_rw/bitlocker
```

#### **ExFAT:**

```bash
gsu mount -t exfat -o loop /data/local/tmp/dislocker/dislocker-file /mnt/media_rw/bitlocker
```

#### **FAT32:**

```bash
gsu mount -t vfat -o loop /data/local/tmp/dislocker/dislocker-file /mnt/media_rw/bitlocker
```

The filesystem type depends on the filesystem contained inside the BitLocker volume.

You can identify the filesystem with:

```bash
file "/data/local/tmp/dislocker/dislocker-file"
```

or, with root:

```bash
gsu blkid /data/local/tmp/dislocker/dislocker-file
```

### 5. Accessing the mounted volume

If the filesystem was mounted with `gsu`, the mount is placed in the global mount namespace and can be accessed by Android processes that share that namespace.

This allows the mounted folder to be accessed using compatible root-capable file managers such as Solid Explorer and File Manager+.

If you mounted the filesystem using `tsu`, it is intended for **Termux-only access**.

### 6. Unmounting

> [!note]
> Unmount the filesystem from the same mount namespace in which it was mounted. Use `gsu` for filesystems mounted with `gsu`, and `tsu` for filesystems mounted with `tsu`.

Unmount the filesystem:

```bash
gsu umount /mnt/media_rw/bitlocker
```

Then remove the Dislocker FUSE mount:

```bash
gsu fusermount3 -u /data/local/tmp/dislocker
```

After unmounting, the directories can be removed if no longer needed:

```bash
gsu rm -rf /data/local/tmp/dislocker /mnt/media_rw/bitlocker
```

## 🤖 Android / Termux considerations

### Root access

Dislocker requires root access to read Android block devices. Use `tsu` for a Termux-only workflow or `gsu` when the decrypted volume needs to be accessible outside Termux.

### FUSE

Dislocker relies on FUSE to expose the decrypted BitLocker filesystem.

Your Android kernel and root environment must provide working FUSE support.

Check whether FUSE is available:

```bash
ls -l /dev/fuse
```

If `/dev/fuse` is unavailable, Dislocker cannot provide its normal FUSE-based output. You'll need to use `dislocker-file` to mount the volume as a flat file.

```bash
su -c "dislocker-file -V /dev/block/sda2 -u'uMyPassword' /data/local/tmp/dislocker-file"
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

## 🔄 Update

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

## 🗑️ Uninstallation

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

## 🏗️ Building

This repository builds Dislocker for Android ARM64 using the Android NDK.

The build script:

1. Downloads and sets up Android NDK.
2. Builds mbedTLS 3.x for Android ARM64.
3. Builds Dislocker against the Android libraries.
4. Packages the resulting binaries and libraries into a Termux-compatible `.deb`.
5. Generates an APT repository.
6. Generates `Packages` and `Packages.gz`.
7. Generates and signs the `Release` metadata.
8. Generates a signed `InRelease`.

GitHub Actions runs the build script and publishes the generated APT repository using GitHub Pages.

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

### Local build

Local builds use the same containerized build environment as CI, but disable
APT repository generation and signing.

**Requirements:**

- [Podman](https://podman.io/)
- [Task](https://taskfile.dev/)

Build Dislocker locally with:

```bash
task rebuild
```
Run `task --list` to see all available tasks.

## 📚 Source

This project packages [Dislocker](https://github.com/Aorimn/dislocker) for Android ARM64.

Original Dislocker project:

https://github.com/Aorimn/dislocker

## 📄 License

See the original [Dislocker](https://github.com/Aorimn/dislocker) project for its licensing information.

The Android build and packaging files in this repository are provided separately from the upstream Dislocker source.

