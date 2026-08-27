#ifndef CONFIG_H
#define CONFIG_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#define VERSION "v1.0.0-albus"

/* Moto Z2 Play (albus) - framebuffer recovery profile */
/* Cell height in pixels; width is derived from font metrics */
#define FONT_SIZE 22

/* Conservative first-pass safe margins for the 1080x1920 panel. */
#define MARGIN_TOP 50
#define MARGIN_BOTTOM 30
#define MARGIN_LEFT 10
#define MARGIN_RIGHT 10

/*
 * Albus rotation test variants:
 *   0 = 0 deg
 *   1 = 90 deg clockwise
 *   2 = 180 deg
 *   3 = 270 deg clockwise
 *
 * CI builds all four variants by replacing ALBUS_ROTATION per isolated job.
 * Keep 0 as the local/default build when no CI variant is selected.
 */
#ifndef ALBUS_ROTATION
#define ALBUS_ROTATION 0
#endif
#define ROTATION ALBUS_ROTATION

#define DISPLAY_TIMEOUT 60 /* seconds of inactivity before sleep */

/* VGA palette defaults (indices into 256-color palette) */
#define DEFAULT_FG 7
#define DEFAULT_BG 0
#define CURSOR_COLOR 15

/* Display format: 0=RGB, 1=BGR */
#define COLOR_BGR 0

/* Shadow buffer helps avoid tearing on the Z2 Play LCD framebuffer. */
#define USE_SHADOW_BUFFER 1

/* Albus recovery exposes FBDEV, not DRM/KMS. Keep CRTC blank disabled. */
#define USE_CRTC_BLANK 0

/* DRM is kept as an upstream-compatible probe; recovery currently exposes no /dev/dri. */
#define DRM_DEVICE "/dev/dri/card0"
#define DRM_MAJOR 226
#define DRM_MINOR 0
#define DRM_CONN_ID 0
#define DRM_CRTC_ID 0

/* Qualcomm MDSS primary framebuffer discovered on-device. */
#define FB_DEVICE "/dev/graphics/fb0"
#define FB_DEVICE_ALT "/dev/fb0"
#define FB_MAJOR 29
#define FB_MINOR 0

/* Recovery provides /sbin/sh -> busybox. */
#define DEFAULT_SHELL "/sbin/sh"
#define TERM_ENV "xterm-256color"

#define IO_BUFSZ 32768
#define SELECT_US 10000
#define ESC_BUF_MAX 256
#define CSI_PARAMS_MAX 16
#define SOCKET_PATH "/tmp/rc.sock"

/* Qualcomm MDSS primary LCD backlight discovered on Moto Z2 Play recovery. */
#define BACKLIGHT_PATH                                                         \
  "/sys/devices/soc/1a00000.qcom,mdss_mdp/1a00000.qcom,mdss_mdp:qcom,mdss_fb_primary/leds/lcd-backlight/brightness"
#define BACKLIGHT_VAL 255

#define LOG(fmt, ...)                                                          \
  do {                                                                         \
    fprintf(stderr, "[rc] " fmt "\n", ##__VA_ARGS__);                          \
    fflush(stderr);                                                            \
  } while (0)

#endif
