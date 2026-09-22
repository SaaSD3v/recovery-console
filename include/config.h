#ifndef CONFIG_H
#define CONFIG_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#define VERSION "v1.0.0-channel"

/* Moto G7 Play (channel) - profile validated on TWRP 3.5.2_10-0 */
/* Cell height in pixels; width is derived from font metrics */
#define FONT_SIZE 22

/*
 * Channel's TWRP tree uses TW_Y_OFFSET=53 and TW_H_OFFSET=-53.
 * Mirror that safe area: shift content down by 53 px without adding
 * an extra bottom inset.
 */
#define MARGIN_TOP 53
#define MARGIN_BOTTOM 0
#define MARGIN_LEFT 10
#define MARGIN_RIGHT 10

/*
 * Channel rotation test variants:
 *   0 = 0 deg
 *   1 = 90 deg clockwise
 *   2 = 180 deg
 *   3 = 270 deg clockwise
 *
 * CI builds all four variants by replacing CHANNEL_ROTATION per isolated job.
 * Keep 0 as the local/default build when no CI variant is selected.
 */
#ifndef CHANNEL_ROTATION
#define CHANNEL_ROTATION 0
#endif
#define ROTATION CHANNEL_ROTATION

#define DISPLAY_TIMEOUT 60 /* seconds of inactivity before sleep */

/* VGA palette defaults (indices into 256-color palette) */
#define DEFAULT_FG 7
#define DEFAULT_BG 0
#define CURSOR_COLOR 15

/* Channel FBDEV layout: R@0, G@8, B@16, A@24. */
#define COLOR_BGR 1

/*
 * Real recovery probe exposes FBDEV only (no /dev/dri). In this codebase
 * USE_SHADOW_BUFFER only changes the DRM path, so keep it disabled here.
 */
#define USE_SHADOW_BUFFER 0

/* Real recovery probe exposes no DRM/KMS; CRTC blanking is not used. */
#define USE_CRTC_BLANK 0

/* No /dev/dri/card* exists on the tested recovery; keep upstream probe harmless. */
#define DRM_DEVICE "/dev/dri/card0"
#define DRM_MAJOR 226
#define DRM_MINOR 0
#define DRM_CONN_ID 0
#define DRM_CRTC_ID 0

/* Verified on-device: /dev/graphics/fb0 = major 29 minor 0, mdssfb_80000. */
#define FB_DEVICE "/dev/graphics/fb0"
#define FB_DEVICE_ALT "/dev/fb0" /* not present on tested TWRP; harmless fallback */
#define FB_MAJOR 29
#define FB_MINOR 0

/* Verified on-device: /bin/sh exists. Match upstream Recovery Console. */
#define DEFAULT_SHELL "/bin/sh"
#define TERM_ENV "xterm-256color"

#define IO_BUFSZ 32768
#define SELECT_US 10000
#define ESC_BUF_MAX 256
#define CSI_PARAMS_MAX 16
#define SOCKET_PATH "/tmp/rc.sock"

/*
 * Verified on-device: /sys/class/leds/lcd-backlight exists and max_brightness=255.
 * The framebuffer reports 720x3024 virtual, 32 bpp, stride 2944, rotate=0.
 */
#define BACKLIGHT_PATH "/sys/class/leds/lcd-backlight/brightness"
#define BACKLIGHT_VAL 255

#define LOG(fmt, ...)                                                          \
  do {                                                                         \
    fprintf(stderr, "[rc] " fmt "\n", ##__VA_ARGS__);                          \
    fflush(stderr);                                                            \
  } while (0)

#endif
