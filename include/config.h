#ifndef CONFIG_H
#define CONFIG_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#define VERSION "v1.0.0-channel"

/* Moto G7 Play (channel) - Qualcomm MDSS framebuffer recovery profile */
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

/* Qualcomm MDSS framebuffer is expected in the normal RGB ordering. */
#define COLOR_BGR 0

/*
 * Channel uses a 720x1512 video-mode LCD panel. Keep the shadow buffer
 * enabled to avoid visible tearing while rendering through FBDEV.
 */
#define USE_SHADOW_BUFFER 1

/* Channel recovery is FBDEV-based; CRTC blanking is not used. */
#define USE_CRTC_BLANK 0

/* Keep the upstream DRM probe/fallback layout intact. */
#define DRM_DEVICE "/dev/dri/card0"
#define DRM_MAJOR 226
#define DRM_MINOR 0
#define DRM_CONN_ID 0
#define DRM_CRTC_ID 0

/* Qualcomm MDSS primary framebuffer exposed by the recovery kernel. */
#define FB_DEVICE "/dev/graphics/fb0"
#define FB_DEVICE_ALT "/dev/fb0"
#define FB_MAJOR 29
#define FB_MINOR 0

/* TWRP recovery shell. */
#define DEFAULT_SHELL "/sbin/sh"
#define TERM_ENV "xterm-256color"

#define IO_BUFSZ 32768
#define SELECT_US 10000
#define ESC_BUF_MAX 256
#define CSI_PARAMS_MAX 16
#define SOCKET_PATH "/tmp/rc.sock"

/*
 * The channel MDSS framebuffer driver registers the panel backlight as
 * the lcd-backlight LED class device. Panel DT sets the range to 1..255.
 */
#define BACKLIGHT_PATH "/sys/class/leds/lcd-backlight/brightness"
#define BACKLIGHT_VAL 255

#define LOG(fmt, ...)                                                          \
  do {                                                                         \
    fprintf(stderr, "[rc] " fmt "\n", ##__VA_ARGS__);                          \
    fflush(stderr);                                                            \
  } while (0)

#endif
