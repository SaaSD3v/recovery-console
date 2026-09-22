# Recovery Console — Moto G7 Play (channel)

Device-specific Recovery Console profile for the Motorola Moto G7 Play (`channel`).

This branch is intentionally limited to the **Recovery Console source/configuration and normal aarch64 binaries**. It does not build, patch, or publish recovery images.

## Repository layout

The Channel work is split into two independent branches:

- **`Channel-Configs`** — this branch. Device configuration, source and normal Recovery Console binary builds.
- **`Channel-Recovery-Image-Builder`** — recovery-as-boot/TWRP installer builder. It consumes `Channel-Configs` and produces the permanent recovery installer ZIP.

The repository `main` branch remains generic and is not used as a Channel dispatcher.

## Device profile

Validated on a Moto G7 Play running TWRP 3.5.2_10-0.

| Item | Channel value |
| --- | --- |
| Architecture | aarch64 |
| Display backend | legacy Qualcomm MDSS FBDEV |
| Primary framebuffer | `/dev/graphics/fb0` |
| FB device | major 29, minor 0 |
| Driver | `mdssfb_80000` |
| Physical panel | 720 × 1512 |
| Virtual framebuffer | 720 × 3024 |
| Bits per pixel | 32 |
| Stride | 2944 bytes |
| Kernel-reported rotation | 0 |
| Backlight | `/sys/class/leds/lcd-backlight/brightness` |
| Backlight maximum | 255 |
| Recovery shell | `/bin/sh` |
| TWRP safe-area top offset | 53 px |
| Recovery Console socket | `/tmp/rc.sock` |

The 720×3024 virtual framebuffer is consistent with two vertically stacked 720×1512 pages. The Recovery Console uses the real framebuffer stride reported by the kernel.

The tested recovery exposes FBDEV and no usable `/dev/dri/card*`, so Channel keeps the upstream DRM probe harmless and falls back to FBDEV.

## Channel configuration

The device-specific settings live in `include/config.h`.

Important values:

```c
#define FONT_SIZE 22
#define MARGIN_TOP 53
#define MARGIN_BOTTOM 0
#define MARGIN_LEFT 10
#define MARGIN_RIGHT 10

#define FB_DEVICE "/dev/graphics/fb0"
#define FB_MAJOR 29
#define FB_MINOR 0

#define DEFAULT_SHELL "/bin/sh"

#define BACKLIGHT_PATH "/sys/class/leds/lcd-backlight/brightness"
#define BACKLIGHT_VAL 255
```

Four rotation variants are supported:

- `portrait-0` → rotation 0 / 0°
- `landscape-90` → rotation 1 / 90° clockwise
- `portrait-180` → rotation 2 / 180°
- `landscape-270` → rotation 3 / 270° clockwise

Because the physical display was removed during validation, framebuffer operation was verified through recovery/ADB/kernel state, but final visual color order and preferred physical orientation still require a connected panel.

## Components used

The Channel implementation is built from the following pieces:

- **Recovery Console upstream:** `Droidspaces/recovery-console`
- **Device profile:** this `Channel-Configs` branch
- **Compiler:** aarch64 musl cross-toolchain from Droidspaces OSS releases
- **Font renderer:** statically linked FreeType
- **Recovery base:** official TeamWin `twrp-installer-3.5.2_10-0-channel.zip`
- **Recovery layout:** recovery-as-boot / A/B
- **Installer logic:** the original TeamWin `META-INF/com/google/android/update-binary`
- **Ramdisk tool:** `magiskboot`
- **Permanent integration path:** the upstream Recovery Console README `init.rc` method
- **Console path inside recovery:** `/system/bin/recovery-console`

The recovery-image branch preserves the TeamWin installer behavior: it reads each installed `boot_a` and `boot_b`, replaces the recovery ramdisk, repacks the existing boot image, and writes it back. Kernel, DTB and boot header come from the device's installed boot images rather than being replaced with unrelated copies.

## Permanent integration

The recovery image builder follows the official Recovery Console permanent-integration layout.

The original stock TWRP service remains in its original init file and receives `disabled`:

```rc
service recovery /system/bin/recovery
    socket recovery stream 422 system system
    seclabel u:r:recovery:s0
    disabled
```

The Recovery Console service and boot trigger are placed in the ramdisk root `/init.rc`:

```rc
service recovery-console /system/bin/recovery-console
    user root
    group root
    oneshot
    disabled
    seclabel u:r:recovery:s0

on boot
    start recovery-console
```

The service itself is marked `disabled` so Android init does not class-start it independently; the explicit `on boot` action starts it once.

The tested TWRP ramdisk already places recovery SELinux in permissive mode during `early-init`, so the builder does not inject an additional SELinux policy rewrite.

## Expected boot behavior

With the permanent installer flashed:

```text
Android
  ↓
reboot recovery
  ↓
recovery init
  ↓
stock TWRP service remains stopped
  ↓
recovery-console starts automatically
  ↓
framebuffer terminal becomes the recovery UI
```

No `start recovery-console` command and no ADB `--attach` are required for the console itself to start.

`--attach` is only a remote client for the already running console session:

```sh
/system/bin/recovery-console --attach
```

This is useful on a device with no screen, but is not part of the permanent boot requirement.

## On-device validation

The permanent Channel build was validated on the real device after installing the native TWRP ZIP and rebooting to recovery.

Immediately after boot:

```text
CONSOLE=running
TWRP=stopped
ADBD=running
```

The process list showed both `recovery-console` and `adbd` alive.

The installed binary and socket were present:

```text
/system/bin/recovery-console
/tmp/rc.sock
```

The live ramdisk showed the permanent service in `/init.rc` and the stock `service recovery` marked `disabled`.

ADB attach connected successfully to the running session:

```text
channel:/ # echo CHANNEL_CONSOLE_OK
CHANNEL_CONSOLE_OK
channel
running
stopped
```

Kernel logs also confirmed:

- `fb0` registered as 720×1512;
- `/system/bin/recovery-console` executed during recovery boot;
- the MDSS panel/display path was brought up by the console;
- ADB USB configuration completed while the console remained active.

### Exiting the console

Typing `exit` inside the attached shell exits the **main PTY shell**, not merely the ADB viewer.

That intentionally reaches the upstream Recovery Console cleanup path, which executes:

```text
start recovery
```

The on-device log confirmed that sequence: the console removed `/tmp/rc.sock`, Android init received `start recovery`, the Recovery Console exited with status 0, and TWRP started.

So:

- closing/disconnecting the ADB client leaves the permanent console alive;
- sending `exit` to the console shell intentionally hands control back to TWRP.

## Root requirements

Recovery Console does **not** depend on Magisk or KernelSU for runtime privilege.

Android init launches the recovery service as:

```rc
user root
group root
```

The validation kernel happened to contain KernelSU, which logged execution of `/system/bin/recovery-console`, but KernelSU was not responsible for starting or granting root to the service.

## Normal binary builds

The workflow stored in this branch builds only the normal Channel binaries. It does not create a recovery image.

A push to `Channel-Configs` builds all four orientations and uploads a tarball for each variant.

Artifacts contain:

```text
recovery-console-channel-aarch64-portrait-0
recovery-console-channel-aarch64-landscape-90
recovery-console-channel-aarch64-portrait-180
recovery-console-channel-aarch64-landscape-270
```

For a flashable permanent recovery installer, use the **`Channel-Recovery-Image-Builder`** branch instead.

## Upstream project

Recovery Console provides framebuffer/DRM terminal rendering, physical-key input, terminal emulation, ADB attach support and recovery lifecycle handling.

Upstream project:

`Droidspaces/recovery-console`

This Channel branch only carries the device-specific configuration and validation required for the Moto G7 Play.
