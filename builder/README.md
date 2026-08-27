# Recovery Image Builder

This branch is intentionally separate from `main` and device configuration branches.
Its only job is to compile a selected device profile of Recovery Console and inject it into a base Android recovery image.

## What it does

For each request the workflow:

1. Checks out the requested device source ref (`SOURCE_REF`).
2. Builds the requested CPU architecture.
3. Rebuilds it four times with `ROTATION=0,1,2,3`.
4. Downloads the supplied base `recovery.img`.
5. Downloads the current official Magisk APK and extracts the Linux x86_64 `magiskboot` binary.
6. Unpacks the recovery image with `magiskboot`.
7. Adds `recovery-console` to the ramdisk.
8. Adds a disabled `recovery-console` init service.
9. Re-packs the image while preserving the original boot-image structure handled by `magiskboot`.
10. Re-opens the generated image and verifies that the binary and disabled init service exist.
11. Uploads four integrated recovery images as GitHub Actions artifacts.

The builder never adds an `on boot -> start recovery-console` rule. The normal recovery remains the default UI.

## Why this branch uses a push request file

GitHub only dispatches `workflow_dispatch` events when the workflow exists on the repository default branch. We keep `main` identical to upstream, so this builder is triggered by pushes to a request file on `Recovery-Image-Builder` instead.

## How to run a build

1. Put the base `recovery.img` at a direct HTTPS URL. A GitHub Release asset is recommended.
2. Copy `builder/REQUEST.env.example` to `builder/REQUEST.env` on this branch.
3. Edit the values.
4. Commit/push `builder/REQUEST.env`.
5. Open GitHub Actions and wait for `Recovery Image Builder`.
6. Download the four artifacts.

Example:

```sh
SOURCE_REF=Albus-Configs
RECOVERY_URL='https://github.com/USER/REPO/releases/download/base/recovery.img'
ARCHITECTURE=aarch64
OUTPUT_PREFIX=albus-recovery-console
SECLABEL='u:r:recovery:s0'
REQUEST_ID=1
```

To rebuild the same configuration, increment `REQUEST_ID` and commit again.

## Generated variants

For a prefix such as `albus-recovery-console` and architecture `aarch64`:

```text
albus-recovery-console-aarch64-rot0-0deg.img
albus-recovery-console-aarch64-rot1-90deg.img
albus-recovery-console-aarch64-rot2-180deg.img
albus-recovery-console-aarch64-rot3-270deg.img
```

Each artifact also contains a SHA-256 file and BUILD-INFO text.

## Injected init service

The builder injects a service equivalent to:

```rc
service recovery-console /sbin/recovery-console
    user root
    group root
    oneshot
    disabled
    seclabel u:r:recovery:s0
```

If `/sbin` is not already part of the ramdisk layout, the binary is installed as `/recovery-console` instead and the service path is adjusted automatically.

There is intentionally no autostart rule. After booting the generated recovery, start it with:

```sh
adb shell start recovery-console
```

Then attach with the actual installed path, normally:

```sh
adb shell /sbin/recovery-console --attach
```

## Supported source profiles

This branch is a generic **image integration mechanism**, not a universal hardware configuration generator.
`SOURCE_REF` must already contain the correct device-specific Recovery Console settings such as backlight path, display quirks, shell path, margins, and other required configuration.

Supported CPU build targets:

- `aarch64`
- `armhf`
- `x86_64`
- `x86`

## Safety / fail-closed behavior

The integration step fails instead of producing an image when:

- `magiskboot` cannot unpack the image;
- the image has no ramdisk;
- no supported recovery/init rc file can be found;
- the Recovery Console binary is missing;
- the output image is empty;
- the generated image cannot be unpacked again;
- the injected binary or disabled init service cannot be verified after repacking.

The base recovery image itself is never modified in place.
