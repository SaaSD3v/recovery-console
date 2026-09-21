# Channel Recovery-as-Boot Builder

This branch is dedicated to the Moto G7 Play (`channel`).

Unlike devices with a standalone recovery partition, Channel uses recovery-as-boot (`BOARD_USES_RECOVERY_AS_BOOT := true`). The official TWRP installer patches both `boot_a` and `boot_b` by replacing their ramdisk.

For that reason this builder uses the official Channel TWRP installer ZIP as the source of the recovery ramdisk instead of treating recovery as a standalone partition image.

## GitHub Actions manual builder

The repository default branch contains the **Channel TWRP + Recovery Console** workflow so it is available through the GitHub Actions **Run workflow** UI.

Inputs:

- `orientation=all` builds 0, 90, 180 and 270 degrees.
- `portrait-0` builds rotation 0 only.
- `landscape-90` builds rotation 1 only.
- `portrait-180` builds rotation 2 only.
- `landscape-270` builds rotation 3 only.
- `twrp_version` selects an official Channel installer version.
- `publish_release` optionally publishes the final installer ZIP(s) in a GitHub Release; Actions artifacts are always uploaded.

The manual workflow opens the official Team Win download page for the selected version, follows the installer link exposed by that page, builds `Channel-Configs`, integrates the console into the ZIP's recovery ramdisk, and uploads the final native TWRP installer.

## Build flow

For each rotation (0/90/180/270 degrees) the workflow:

1. Checks out `Channel-Configs`.
2. Builds the aarch64 Recovery Console binary.
3. Downloads or reads a Channel TWRP installer ZIP.
4. Locates `ramdisk-twrp.cpio` or `ramdisk-recovery.cpio` inside the ZIP.
5. Injects `recovery-console` into that ramdisk.
6. Follows the upstream README permanent method exactly: adds `disabled` to the original stock `service recovery`, installs the console at `/system/bin/recovery-console`, and writes the console service plus `on boot -> start recovery-console` into the ramdisk root `/init.rc`.
7. Rebuilds the TWRP installer ZIP without changing its recovery-as-boot installer logic.
8. Extracts the resulting modified ramdisk as a separate artifact for inspection.
9. Uploads the modified installer ZIP, ramdisk CPIO, SHA-256 and build information.

The original Channel TWRP `update-binary` remains responsible for installation. It reads each device slot's current `boot_a` and `boot_b`, replaces only the ramdisk, repacks with `magiskboot`, and writes the result back. This preserves the kernel/DTB/header from the boot image already installed on the phone.

## Input

Copy `builder/REQUEST.env.example` to `builder/REQUEST.env`.

Either provide a direct ZIP URL:

```sh
SOURCE_REF=Channel-Configs
TWRP_ZIP_URL='https://example.com/twrp-channel-installer.zip'
TWRP_ZIP_PATH=''
TWRP_ZIP_SHA256=''
ARCHITECTURE=aarch64
OUTPUT_PREFIX=channel-recovery-console
SECLABEL='u:r:recovery:s0'
MAGISK_APK_URL=''
REQUEST_ID=1
```

or commit/upload the installer to this branch:

```sh
SOURCE_REF=Channel-Configs
TWRP_ZIP_URL=''
TWRP_ZIP_PATH='builder/input/twrp-channel-installer.zip'
TWRP_ZIP_SHA256=''
ARCHITECTURE=aarch64
OUTPUT_PREFIX=channel-recovery-console
SECLABEL='u:r:recovery:s0'
MAGISK_APK_URL=''
REQUEST_ID=1
```

A push changing `builder/REQUEST.env` on `Channel-Recovery-Image-Builder` triggers the build.

## Outputs

Each rotation produces an installable ZIP such as:

```text
channel-recovery-console-aarch64-rot0-0deg.zip
channel-recovery-console-aarch64-rot1-90deg.zip
channel-recovery-console-aarch64-rot2-180deg.zip
channel-recovery-console-aarch64-rot3-270deg.zip
```

Each artifact also contains the modified recovery ramdisk CPIO, its build information, and the ZIP SHA-256.

## Runtime behavior

This builder uses the project's documented **Permanent Integration** mode.

On recovery boot:

```text
init
  -> stock service recovery = disabled
  -> on boot
  -> start recovery-console
```

Recovery Console is therefore the primary recovery UI. The console service itself remains marked `disabled` so it is not class-started twice; the explicit `on boot` action starts it.

If the console exits normally, its existing cleanup path can explicitly run `start recovery`, which remains a manual fallback to TWRP.

For the tested Channel TWRP 3.5.2_10-0 ramdisk the console binary follows the upstream documented path exactly:

```sh
/system/bin/recovery-console
```

ADB attach:

```sh
/system/bin/recovery-console --attach
```

The Channel profile uses the upstream `main.c` unchanged. Its ramdisk exposes `/bin -> /system/bin`, so the upstream `/bin/sh` lifecycle commands work without a device-specific source patch.

The tested TWRP 3.5.2_10-0 ramdisk already forces SELinux permissive in `early-init` with `write /sys/fs/selinux/enforce 0`, satisfying the upstream SELinux requirement without an extra policy rewrite.

## Why the output is primarily a ZIP, not recovery.img

Channel has no independent recovery partition. The persistent and firmware-safe artifact is therefore the modified TWRP installer ZIP. A standalone bootable image can only be produced safely when a matching Channel boot/recovery-as-boot image is supplied as an additional base, because the image also contains kernel/DTB/header data that is not present in the installer ramdisk alone.
