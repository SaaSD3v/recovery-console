# Recovery Console — Moto G7 Play (`channel`)

Recovery Console port for the Motorola Moto G7 Play (`channel`), adapted for the device's recovery environment.

## Configuration

```c
#define FONT_SIZE 22

#define MARGIN_TOP 53
#define MARGIN_BOTTOM 0
#define MARGIN_LEFT 10
#define MARGIN_RIGHT 10

#define DISPLAY_TIMEOUT 60

#define COLOR_BGR 1

#define USE_SHADOW_BUFFER 0
#define USE_CRTC_BLANK 0

#define FB_DEVICE "/dev/graphics/fb0"
#define FB_DEVICE_ALT "/dev/fb0"
#define FB_MAJOR 29
#define FB_MINOR 0

#define DEFAULT_SHELL "/bin/sh"

#define BACKLIGHT_PATH "/sys/class/leds/lcd-backlight/brightness"
#define BACKLIGHT_VAL 255
```

## Display

Recovery uses FBDEV through the primary Qualcomm MDSS framebuffer:

```text
Driver:       mdssfb_80000
Device:       /dev/graphics/fb0
Resolution:   720x1512
Virtual:      720x3024
BPP:          32
Stride:       2944
Rotation:     0
```

Pixel layout:

```text
R: 0:8
G: 8:8
B: 16:8
A: 24:8
```

The Channel profile uses:

```c
#define COLOR_BGR 1
```

## Shell

The Channel recovery provides:

```text
/bin/sh
```

So the profile uses:

```c
#define DEFAULT_SHELL "/bin/sh"
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

Rotation is selected at build time through `CHANNEL_ROTATION`.

## Base

```text
Device: Moto G7 Play
Codename: channel
TWRP: 3.5.2_10-0
Kernel: 4.9.206-perf+
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
replay buffer
input hotplug
VT fallback
Volume scrolling
exit -> TWRP
manual Recovery Console restart
ADB during Recovery Console
```

## Credits

Forked from [Droidspaces/recovery-console](https://github.com/Droidspaces/recovery-console).

Recovery Console core belongs to the upstream project. This fork contains the Moto G7 Play (`channel`) port, device configuration, build adaptations, and validation.
