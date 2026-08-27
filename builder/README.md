# Recovery Image Builder

This branch is intentionally separate from `main` and device configuration branches.
Its only job is to compile a selected device profile of Recovery Console and inject it into a base Android recovery image.

## What it does

For each request the workflow:

1. Checks out the requested device source ref (`SOURCE_REF`).
2. Builds the requested CPU architecture.
3. Rebuilds it four times with `ROTATION=0,1,2,3`.
4. Gets the base `recovery.img` from either a direct HTTPS URL or a file stored in this builder branch.
5. Optionally verifies the base image SHA-256 before touching it.
6. Downloads the official Magisk APK and extracts the Linux x86_64 `magiskboot` binary.
7. Unpacks the recovery image with `magiskboot`.
8. Adds `recovery-console` to the ramdisk.
9. Adds a disabled `recovery-console` init service.
10. Re-packs the image while preserving the boot-image structure handled by `magiskboot`.
11. Re-opens the generated image and verifies that the binary and disabled init service exist.
12. Uploads four integrated recovery images as GitHub Actions artifacts.

The builder never adds an `on boot -> start recovery-console` rule. The normal recovery remains the default UI.

## Why this branch uses a push request file

GitHub only dispatches `workflow_dispatch` events when the workflow exists on the repository default branch. We keep `main` identical to upstream, so this builder is triggered by pushes to `builder/REQUEST.env` on `Recovery-Image-Builder` instead.

## How to run a build

### Option A - recovery image inside the builder branch

1. Upload the base image as `builder/input/recovery.img` on `Recovery-Image-Builder`.
2. Copy `builder/REQUEST.env.example` to `builder/REQUEST.env`.
3. Use:

```sh
SOURCE_REF=Albus-Configs
RECOVERY_URL=''
RECOVERY_PATH='builder/input/recovery.img'
RECOVERY_SHA256='optional-sha256-here'
ARCHITECTURE=aarch64
OUTPUT_PREFIX=albus-recovery-console
SECLABEL='u:r:recovery:s0'
MAGISK_APK_URL=''
REQUEST_ID=1
```

4. Commit/push `builder/REQUEST.env`.

### Option B - direct HTTPS recovery URL

Use:

```sh
SOURCE_REF=Albus-Configs
RECOVERY_URL='https://github.com/USER/REPO/releases/download/base/recovery.img'
RECOVERY_PATH=''
RECOVERY_SHA256='optional-sha256-here'
ARCHITECTURE=aarch64
OUTPUT_PREFIX=albus-recovery-console
SECLABEL='u:r:recovery:s0'
MAGISK_APK_URL=''
REQUEST_ID=1
```

Use exactly one of `RECOVERY_URL` or `RECOVERY_PATH`.

After pushing the request, open GitHub Actions and wait for `Recovery Image Builder`. To rebuild the exact same configuration, increment `REQUEST_ID` and commit again.

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

The builder normally injects a service equivalent to:

```rc
service recovery-console /sbin/recovery-console
    user root
    group root
    oneshot
    disabled
    seclabel u:r:recovery:s0
```

If the recovery does not already use `/sbin/recovery`, the builder installs the binary as `/recovery-console` instead and adjusts the service path automatically.

There is intentionally no autostart rule. After booting the generated recovery, start it with:

```sh
adb shell start recovery-console
```

Then attach with the actual installed path, normally:

```sh
adb shell /sbin/recovery-console --attach
```

or, when the builder selected the root path:

```sh
adb shell /recovery-console --attach
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
- a supplied base-image SHA-256 does not match;
- the output image is empty;
- the generated image cannot be unpacked again;
- the injected binary or disabled init service cannot be verified after repacking.

The base recovery image itself is never modified in place.
