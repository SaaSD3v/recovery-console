#!/bin/sh
# Recovery Console - compact read-only requirements probe
# Informational only: does not write sysfs, create nodes, stop recovery,
# change VT/SELinux, or touch framebuffer contents.

PATH=/sbin:/system/bin:/system/xbin:/vendor/bin:/odm/bin:/usr/bin:/bin:$PATH
export PATH

ok()      { printf '[EXISTS]      %-20s %s\n' "$1" "$2"; }
no()      { printf '[NOT FOUND]   %-20s %s\n' "$1" "$2"; }
auto()    { printf '[AUTO]        %-20s %s\n' "$1" "$2"; }
manual()  { printf '[MANUAL]      %-20s %s\n' "$1" "$2"; }
info()    { printf '[INFO]        %-20s %s\n' "$1" "$2"; }
summary() { printf '  %-22s : %s\n' "$1" "$2"; }

first_exec() {
    for p in "$@"; do
        [ -x "$p" ] && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

find_backlight() {
    for d in /sys/class/backlight/*; do
        [ -f "$d/brightness" ] && { printf '%s\n' "$d/brightness"; return 0; }
    done
    if command -v find >/dev/null 2>&1; then
        find /sys/devices -type f -name brightness 2>/dev/null \
            | grep -E 'backlight|lcd|panel|leds' \
            | head -n 1
    fi
}

printf '%s\n' '============================================================'
printf '%s\n' ' RECOVERY CONSOLE - DEVICE REQUIREMENTS CHECK'
printf '%s\n' ' Read-only / informational only'
printf '%s\n' '============================================================'

# Architecture / binary selection
ARCH=$(uname -m 2>/dev/null)
if [ -n "$ARCH" ]; then
    ok 'Architecture' "$ARCH"
else
    no 'Architecture' 'uname unavailable'
    ARCH='<unknown>'
fi

# DRM/KMS device
DRM=''
for p in /dev/dri/card*; do
    [ -e "$p" ] && { DRM=$p; break; }
done
if [ -n "$DRM" ]; then
    ok 'DRM/KMS' "$DRM"
else
    no 'DRM/KMS' 'no /dev/dri/card*'
fi

# Legacy framebuffer device
FB=''
for p in /dev/graphics/fb* /dev/fb*; do
    [ -e "$p" ] && { FB=$p; break; }
done
if [ -n "$FB" ]; then
    ok 'FBDEV' "$FB"
else
    no 'FBDEV' 'no framebuffer node'
fi

# Effective display backend availability
if [ -n "$DRM" ]; then
    DISPLAY_BACKEND='DRM'
    ok 'Display backend' "DRM candidate available ($DRM)"
elif [ -n "$FB" ]; then
    DISPLAY_BACKEND='FBDEV'
    ok 'Display backend' "FBDEV candidate available ($FB)"
else
    DISPLAY_BACKEND='NONE'
    no 'Display backend' 'neither DRM nor FBDEV exists'
fi

# Framebuffer facts useful to the current implementation
FBNAME=''
VIRTUAL=''
BPP=''
STRIDE=''
ROT=''
if [ -d /sys/class/graphics/fb0 ]; then
    VIRTUAL=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null)
    BPP=$(cat /sys/class/graphics/fb0/bits_per_pixel 2>/dev/null)
    STRIDE=$(cat /sys/class/graphics/fb0/stride 2>/dev/null)
    FBNAME=$(cat /sys/class/graphics/fb0/name 2>/dev/null)
    ROT=$(cat /sys/class/graphics/fb0/rotate 2>/dev/null)
    [ -n "$FBNAME" ] && info 'FB name' "$FBNAME"
    [ -n "$VIRTUAL" ] && info 'FB virtual size' "$VIRTUAL"
    [ -n "$BPP" ] && info 'FB bits/pixel' "$BPP"
    [ -n "$STRIDE" ] && info 'FB stride' "$STRIDE"
fi

# Backlight path + usable brightness value
BL=$(find_backlight)
MAXBL=''
CURBL=''
if [ -n "$BL" ] && [ -e "$BL" ]; then
    ok 'BACKLIGHT_PATH' "$BL"
    BLDIR=${BL%/brightness}
    MAXBL=$(cat "$BLDIR/max_brightness" 2>/dev/null)
    CURBL=$(cat "$BL" 2>/dev/null)
    [ -n "$MAXBL" ] && ok 'max_brightness' "$MAXBL" || no 'max_brightness' 'not exposed next to brightness'
    [ -n "$CURBL" ] && info 'current brightness' "$CURBL"
else
    no 'BACKLIGHT_PATH' 'no brightness candidate found'
    no 'max_brightness' 'cannot determine without backlight path'
fi

# Shell used by --exec and recovery start/stop
SHELL_PATH=$(first_exec /bin/sh /system/bin/sh /sbin/sh /vendor/bin/sh /system/xbin/sh)
SHELL_DISPLAY=''
if [ -n "$SHELL_PATH" ]; then
    TARGET=''
    command -v readlink >/dev/null 2>&1 && TARGET=$(readlink "$SHELL_PATH" 2>/dev/null)
    if [ -n "$TARGET" ]; then
        SHELL_DISPLAY="$SHELL_PATH -> $TARGET"
        ok 'DEFAULT_SHELL' "$SHELL_DISPLAY"
    else
        SHELL_DISPLAY="$SHELL_PATH"
        ok 'DEFAULT_SHELL' "$SHELL_DISPLAY"
    fi
else
    SHELL_DISPLAY='<not found>'
    no 'DEFAULT_SHELL' 'no known executable sh path'
fi

# Recovery service used by current stop/start behavior
REC=''
if command -v getprop >/dev/null 2>&1; then
    REC=$(getprop init.svc.recovery 2>/dev/null)
    if [ -n "$REC" ]; then
        ok 'recovery service' "init.svc.recovery=$REC"
    else
        no 'recovery service' 'init.svc.recovery property absent'
    fi
else
    no 'recovery service' 'getprop unavailable'
fi

# Things already automatic in current C code
auto 'DRM connector ID' 'current code auto-picks when DRM_CONN_ID=0'
auto 'DRM CRTC ID' 'current code resolves when DRM_CRTC_ID=0'
auto 'DRM -> FBDEV' 'current code tries DRM first, then FBDEV'
auto 'FB geometry' 'current code gets width/height/pitch/size via FB ioctls'
auto 'DRM resolution' 'current code uses preferred connected mode'

# Device-specific values documented as requiring customization and not safely
# inferable from mere node existence.
if [ -n "$ROT" ]; then
    info 'Rotation hint' "kernel reports $ROT (still needs visual validation)"
else
    manual 'ROTATION' 'no reliable universal value; visual/device validation needed'
fi
manual 'MARGINS' 'notch/cutout/safe-area requires device/visual knowledge'
manual 'COLOR_BGR' 'must be derived from pixel format/bitfields or visual validation'
manual 'SHADOW_BUFFER' 'panel/tearing behavior; use safe default then validate'
manual 'CRTC_BLANK' 'panel/vendor behavior; use safe default then validate'

printf '%s\n' '------------------------------------------------------------'
if [ -n "$DRM" ] || [ -n "$FB" ]; then
    printf '%s\n' '[RESULT] Display device: AVAILABLE'
else
    printf '%s\n' '[RESULT] Display device: MISSING'
fi
[ -n "$BL" ] && printf '%s\n' '[RESULT] Backlight:      AVAILABLE' || printf '%s\n' '[RESULT] Backlight:      MISSING'
[ -n "$SHELL_PATH" ] && printf '%s\n' '[RESULT] Shell:          AVAILABLE' || printf '%s\n' '[RESULT] Shell:          MISSING'

printf '%s\n' '============================================================'
printf '%s\n' ' FINAL SUMMARY - VALUES FOUND FOR THIS DEVICE'
printf '%s\n' '============================================================'
summary 'ARCH' "$ARCH"
summary 'DISPLAY_BACKEND' "$DISPLAY_BACKEND"
summary 'DRM_DEVICE' "${DRM:-<not found>}"
summary 'FB_DEVICE' "${FB:-<not found>}"
summary 'FB_NAME' "${FBNAME:-<not reported>}"
summary 'FB_VIRTUAL_SIZE' "${VIRTUAL:-<not reported>}"
summary 'FB_BPP' "${BPP:-<not reported>}"
summary 'FB_STRIDE' "${STRIDE:-<not reported>}"
summary 'BACKLIGHT_PATH' "${BL:-<not found>}"
summary 'BACKLIGHT_MAX' "${MAXBL:-<not reported>}"
summary 'BACKLIGHT_CURRENT' "${CURBL:-<not reported>}"
summary 'DEFAULT_SHELL' "$SHELL_DISPLAY"
summary 'RECOVERY_SERVICE' "${REC:-<not found>}"
summary 'ROTATION_HINT' "${ROT:-<not reported / manual>}"
summary 'MARGINS' '<manual / visual validation>'
summary 'COLOR_BGR' '<manual / pixel-format validation>'
summary 'USE_SHADOW_BUFFER' '<manual / panel behavior>'
summary 'USE_CRTC_BLANK' '<manual / panel behavior>'
printf '%s\n' '============================================================'
printf '%s\n' ' Read-only probe complete. No device settings were changed.'
printf '%s\n' '============================================================'
