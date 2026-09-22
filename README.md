# Recovery Console — Moto Z2 Play (`albus`)

Recovery Console port for the Motorola Moto Z2 Play (`albus`), adapted for the device's recovery environment.

## Configuration

```c
#define FONT_SIZE 22

#define MARGIN_TOP 50
#define MARGIN_BOTTOM 30
#define MARGIN_LEFT 10
#define MARGIN_RIGHT 10

#define DISPLAY_TIMEOUT 60

#define COLOR_BGR 1

#define USE_SHADOW_BUFFER 1
#define USE_CRTC_BLANK 0

#define FB_DEVICE "/dev/graphics/fb0"
#define FB_DEVICE_ALT "/dev/fb0"
#define FB_MAJOR 29
#define FB_MINOR 0

#define DEFAULT_SHELL "/sbin/sh"

#define BACKLIGHT_PATH \
  "/sys/devices/soc/1a00000.qcom,mdss_mdp/1a00000.qcom,mdss_mdp:qcom,mdss_fb_primary/leds/lcd-backlight/brightness"

#define BACKLIGHT_VAL 255
```

## Display

Recovery uses FBDEV through the primary Qualcomm MDSS framebuffer:

```text
Driver:       mdssfb_90000
Device:       /dev/graphics/fb0
Resolution:   1080x1920
Virtual:      1080x3840
BPP:          32
Stride:       4352
Rotation:     0
```

Pixel layout:

```text
R: 0:8
G: 8:8
B: 16:8
A: 24:8
```

The Albus profile uses:

```c
#define COLOR_BGR 1
```

## Shell

The Albus recovery provides:

```text
/sbin/sh -> busybox
```

So the profile uses:

```c
#define DEFAULT_SHELL "/sbin/sh"
```

## Input

Validated support for:

```text
Power
Volume Up
Volume Down
Input hotplug
```

Volume keys control console scrolling, while Power controls display blank/wake.

## Integration

Recovery Console starts automatically during recovery boot and keeps TWRP stopped while it is active.

When the primary shell exits with:

```sh
exit
```

Recovery Console exits and starts the normal recovery service again.

## Build

The build generates the following rotation variants:

```text
portrait-0
landscape-90
portrait-180
landscape-270
```

Rotation is selected at build time through `ALBUS_ROTATION`.

## Base

```text
Device: Moto Z2 Play
Codename: albus
TWRP: 3.5.0_9-0
Kernel: 3.18.71
Architecture: aarch64
```

## Status

Validated on-device:

```text
Recovery Console startup
FBDEV rendering
RGB/BGR framebuffer layout
PTY shell
Unix socket
attach / reconnect
Power blank / wake
60s display timeout
Volume scrolling
input hotplug
exit -> TWRP
ADB during Recovery Console
```

## Credits

Forked from [Droidspaces/recovery-console](https://github.com/Droidspaces/recovery-console).

Recovery Console core belongs to the upstream project. This fork contains the Moto Z2 Play (`albus`) port, device configuration, build adaptations, and validation.
