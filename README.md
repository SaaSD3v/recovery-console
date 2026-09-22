# Recovery Console — Moto Z2 Play (albus)

Device-specific Recovery Console profile for the Motorola Moto Z2 Play (`albus`).

This branch owns only the **Recovery Console device configuration and normal aarch64 binaries**. Recovery images are built separately in `Albus-Recovery-Image-Builder`.

## Branch separation

- **`Albus-Configs`** — this branch: source/config and standalone Recovery Console binaries.
- **`Albus-Recovery-Image-Builder`** — known-good kernel/TWRP base plus permanent Recovery Console image integration.

The repository `main` branch remains generic.

## Albus profile

| Item | Value |
| --- | --- |
| Architecture | aarch64 |
| Display backend | Qualcomm MDSS FBDEV |
| Primary framebuffer | `/dev/graphics/fb0` |
| Physical panel profile | 1080 × 1920 |
| Recovery shell | `/sbin/sh` → BusyBox |
| Backlight | `/sys/devices/soc/1a00000.qcom,mdss_mdp/1a00000.qcom,mdss_mdp:qcom,mdss_fb_primary/leds/lcd-backlight/brightness` |
| Backlight value | 255 |
| Console socket | `/tmp/rc.sock` |
| DRM | no recovery DRM/KMS path used |

The device-specific settings live in `include/config.h`.

Four build orientations are available:

- `portrait-0`
- `landscape-90`
- `portrait-180`
- `landscape-270`

## Normal binary CI

A push to `Albus-Configs` builds four static aarch64 Recovery Console binaries, one for each orientation.

These artifacts are **not recovery images**. For a flashable `recovery.img`, use `Albus-Recovery-Image-Builder`.

## Permanent recovery integration

The recovery-image branch follows the official Recovery Console permanent `init.rc` method:

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

The original stock recovery service receives `disabled`.

Albus has one device-specific shell difference from the Channel profile: the known-good recovery ramdisk exposes `/sbin/sh` through BusyBox and does not provide the same `/bin/sh` layout, so `DEFAULT_SHELL` is `/sbin/sh`.

## Known-good recovery image path

The flashable image builder is intentionally pinned to the known-good Albus recipe:

- source snapshot: `SaaSD3v/albus-builder@a567dec13ee75bb50b0640525b20b5fc22ff6eac`
- kernel: `SaaSD3v/android_kernel_motorola_msm8996`
- kernel commit: `9a7416218ae637c4120c417b31428bb0747fdfdf`
- TWRP base: `twrp-3.5.0_9-0-albus.img`
- TWRP SHA-256: `4c42bfee165ea99e2663284a3634135786e157bd6cc492fcbe0d9bd3430e9261`
- ramdisk compression: LZMA
- image repack mode: `magiskboot unpack -n` / `repack -n`

The recovery builder rejects an image if the kernel or DT differs from the known-good base after Recovery Console integration.

## Upstream

Base project: `Droidspaces/recovery-console`.

This branch contains only the Albus-specific configuration and standalone binary build pipeline.
