#!/bin/sh
# Recovery Console - read-only device information probe
#
# This script is intentionally informational only. It does NOT write to sysfs,
# create device nodes, stop/start recovery, change VT state, change SELinux,
# mmap a framebuffer, or alter any device setting.
#
# Run it with a shell that actually exists in the recovery, for example:
#   /sbin/sh /tmp/recovery-console-device-info.sh
#   /system/bin/sh /tmp/recovery-console-device-info.sh

PATH=/sbin:/system/bin:/system/xbin:/vendor/bin:/odm/bin:/usr/bin:/bin:$PATH
export PATH

say() { printf '%s\n' "$*"; }
section() {
    say ""
    say "============================================================"
    say "$1"
    say "============================================================"
}
found()   { say "[FOUND]   $*"; }
missing() { say "[MISSING] $*"; }
info()    { say "[INFO]    $*"; }
manual()  { say "[MANUAL]  $*"; }
warn()    { say "[WARN]    $*"; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

show_file() {
    label=$1
    path=$2
    if [ -e "$path" ]; then
        if [ -r "$path" ]; then
            value=$(cat "$path" 2>/dev/null)
            [ -n "$value" ] || value="<empty>"
            found "$label: $path = $value"
        else
            found "$label: $path (exists, not readable)"
        fi
    else
        missing "$label: $path"
    fi
}

show_node() {
    path=$1
    if [ -e "$path" ]; then
        found "device node: $path"
        ls -l "$path" 2>/dev/null | sed 's/^/           /'
        if have_cmd stat; then
            # %t:%T is the device major:minor in hexadecimal on GNU/BusyBox stat.
            hexdev=$(stat -c '%t:%T' "$path" 2>/dev/null)
            [ -n "$hexdev" ] && info "$path major:minor (hex) = $hexdev"
        fi
    else
        missing "device node: $path"
    fi
}

first_existing_shell=""
for s in /bin/sh /system/bin/sh /sbin/sh /vendor/bin/sh /system/xbin/sh; do
    if [ -x "$s" ]; then
        [ -n "$first_existing_shell" ] || first_existing_shell=$s
    fi
done

section "1. DEVICE / KERNEL / ARCHITECTURE"
if have_cmd uname; then
    info "uname -a: $(uname -a 2>/dev/null)"
    info "architecture: $(uname -m 2>/dev/null)"
else
    missing "uname"
fi

if have_cmd getprop; then
    for prop in \
        ro.product.manufacturer \
        ro.product.model \
        ro.product.device \
        ro.product.board \
        ro.hardware \
        ro.boot.hardware \
        ro.build.version.release \
        ro.build.version.sdk; do
        value=$(getprop "$prop" 2>/dev/null)
        [ -n "$value" ] && info "$prop=$value"
    done
else
    missing "getprop"
fi

section "2. SHELLS"
for s in /bin/sh /system/bin/sh /sbin/sh /vendor/bin/sh /system/xbin/sh; do
    if [ -x "$s" ]; then
        target=""
        if have_cmd readlink; then
            target=$(readlink "$s" 2>/dev/null)
        fi
        if [ -n "$target" ]; then
            found "$s -> $target"
        else
            found "$s"
        fi
    else
        missing "$s"
    fi
done
if [ -n "$first_existing_shell" ]; then
    info "DEFAULT_SHELL candidate: $first_existing_shell"
else
    warn "No known executable sh path found."
fi

section "3. RECOVERY / INIT SERVICE"
if have_cmd getprop; then
    recovery_state=$(getprop init.svc.recovery 2>/dev/null)
    if [ -n "$recovery_state" ]; then
        found "init.svc.recovery=$recovery_state"
    else
        missing "property init.svc.recovery"
    fi
else
    missing "getprop; cannot query init.svc.recovery"
fi
if have_cmd pidof; then
    rpids=$(pidof recovery 2>/dev/null)
    if [ -n "$rpids" ]; then
        found "recovery process PID(s): $rpids"
    else
        info "No process named exactly 'recovery' found by pidof."
    fi
fi

section "4. DRM / KMS"
drm_count=0
for p in /dev/dri/card*; do
    [ -e "$p" ] || continue
    drm_count=$((drm_count + 1))
    show_node "$p"
done
if [ "$drm_count" -eq 0 ]; then
    missing "No /dev/dri/card* node exists."
else
    found "$drm_count DRM card node(s) found."
fi

connector_count=0
connected_count=0
for c in /sys/class/drm/card*-*; do
    [ -e "$c" ] || continue
    [ -f "$c/status" ] || continue
    connector_count=$((connector_count + 1))
    status=$(cat "$c/status" 2>/dev/null)
    name=${c##*/}
    info "DRM connector: $name status=${status:-unknown}"
    if [ "$status" = "connected" ]; then
        connected_count=$((connected_count + 1))
        if [ -r "$c/modes" ]; then
            modes=$(tr '\n' ' ' < "$c/modes" 2>/dev/null)
            info "  modes: ${modes:-<empty>}"
        fi
        [ -r "$c/enabled" ] && info "  enabled: $(cat "$c/enabled" 2>/dev/null)"
        [ -r "$c/dpms" ] && info "  dpms: $(cat "$c/dpms" 2>/dev/null)"
        [ -r "$c/panel_orientation" ] && info "  panel_orientation hint: $(cat "$c/panel_orientation" 2>/dev/null)"
    fi
done
[ "$connector_count" -eq 0 ] && info "No DRM connector status entries found in /sys/class/drm."
[ "$connected_count" -gt 0 ] && found "$connected_count connected DRM connector(s)."

if have_cmd modetest; then
    info "modetest is available; connector/CRTC details can be inspected with it."
else
    info "modetest is not available (not required by Recovery Console)."
fi

section "5. LEGACY FRAMEBUFFER / FBDEV"
fb_count=0
for p in /dev/graphics/fb* /dev/fb*; do
    [ -e "$p" ] || continue
    fb_count=$((fb_count + 1))
    show_node "$p"
done
if [ "$fb_count" -eq 0 ]; then
    missing "No /dev/graphics/fb* or /dev/fb* node exists."
else
    found "$fb_count framebuffer device node(s) found."
fi

if [ -r /proc/fb ]; then
    info "/proc/fb:"
    sed 's/^/           /' /proc/fb 2>/dev/null
else
    info "/proc/fb is unavailable or unreadable."
fi

fb_sys_count=0
for f in /sys/class/graphics/fb*; do
    [ -d "$f" ] || continue
    fb_sys_count=$((fb_sys_count + 1))
    name=${f##*/}
    say ""
    info "sysfs framebuffer: $name"
    for attr in name modes mode virtual_size bits_per_pixel stride rotate blank pan; do
        if [ -r "$f/$attr" ]; then
            value=$(cat "$f/$attr" 2>/dev/null)
            [ -n "$value" ] || value="<empty>"
            info "  $attr=$value"
        fi
    done
    if [ -e "$f/device" ] && have_cmd readlink; then
        target=$(readlink -f "$f/device" 2>/dev/null)
        [ -n "$target" ] && info "  device=$target"
    fi
done
[ "$fb_sys_count" -eq 0 ] && missing "No /sys/class/graphics/fb* entries found."

if have_cmd fbset; then
    info "fbset exists; read-only fbset -i output follows:"
    fbset -i 2>/dev/null | sed 's/^/           /'
else
    info "fbset not available; framebuffer RGB bitfields cannot be queried from this script through fbset."
fi

section "6. BACKLIGHT"
backlight_count=0
for b in /sys/class/backlight/*; do
    [ -d "$b" ] || continue
    backlight_count=$((backlight_count + 1))
    info "backlight candidate: $b"
    for attr in brightness actual_brightness max_brightness bl_power type; do
        if [ -e "$b/$attr" ]; then
            value=$(cat "$b/$attr" 2>/dev/null)
            [ -n "$value" ] || value="<empty/unreadable>"
            access=""
            [ -r "$b/$attr" ] && access="r"
            [ -w "$b/$attr" ] && access="${access}w"
            info "  $attr=$value access=${access:-none}"
        fi
    done
done

if [ "$backlight_count" -eq 0 ]; then
    missing "No /sys/class/backlight/* entry exists."
    if have_cmd find; then
        info "Searching /sys/devices for likely brightness nodes (read-only)..."
        find /sys/devices -type f -name brightness 2>/dev/null \
            | grep -E 'backlight|lcd|panel|leds' \
            | head -n 20 \
            | sed 's/^/[INFO]      candidate: /'
    else
        info "find is unavailable; extended backlight search skipped."
    fi
else
    found "$backlight_count /sys/class/backlight candidate(s)."
fi

section "7. VT / TTY"
for t in /dev/tty0 /dev/tty1 /dev/tty /dev/console; do
    if [ -e "$t" ]; then
        show_node "$t"
    else
        missing "$t"
    fi
done

section "8. INPUT DEVICES"
input_count=0
for e in /dev/input/event*; do
    [ -e "$e" ] || continue
    input_count=$((input_count + 1))
    show_node "$e"
done
if [ "$input_count" -eq 0 ]; then
    missing "No /dev/input/event* nodes found."
else
    found "$input_count input event node(s) found."
fi
if [ -r /proc/bus/input/devices ]; then
    info "Kernel input inventory (/proc/bus/input/devices):"
    sed 's/^/           /' /proc/bus/input/devices 2>/dev/null
fi

section "9. SELINUX / SECURITY CONTEXT"
if have_cmd getenforce; then
    info "SELinux: $(getenforce 2>/dev/null)"
else
    if [ -r /sys/fs/selinux/enforce ]; then
        en=$(cat /sys/fs/selinux/enforce 2>/dev/null)
        [ "$en" = "1" ] && info "SELinux: Enforcing" || info "SELinux: Permissive/disabled ($en)"
    else
        info "SELinux state could not be determined."
    fi
fi
if have_cmd id; then
    info "identity: $(id 2>/dev/null)"
    z=$(id -Z 2>/dev/null)
    [ -n "$z" ] && info "SELinux context: $z"
fi

section "10. TEMP STORAGE / MEMORY"
if [ -d /tmp ]; then
    found "/tmp exists"
    [ -r /tmp ] && info "/tmp readable=yes" || info "/tmp readable=no"
    [ -w /tmp ] && info "/tmp writable=yes" || info "/tmp writable=no"
    have_cmd df && df /tmp 2>/dev/null | sed 's/^/           /'
else
    missing "/tmp"
fi
if [ -r /proc/meminfo ]; then
    grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null \
        | sed 's/^/           /'
fi

section "11. WHAT THE CURRENT RECOVERY-CONSOLE NEEDS PER DEVICE"
info "README-required device customization:"
say "           1) BACKLIGHT_PATH"
say "           2) ROTATION"
say "           3) MARGIN_TOP / BOTTOM / LEFT / RIGHT"
say "           4) COLOR_BGR"
say "           5) Working DRM or FBDEV backend"
say ""
info "Additional hard-coded implementation values worth replacing/detecting:"
say "           - DRM_DEVICE and DRM device-node major/minor"
say "           - FB_DEVICE / FB_DEVICE_ALT and FB device-node major/minor"
say "           - DEFAULT_SHELL"
say "           - BACKLIGHT_VAL (prefer current/max brightness policy)"
say "           - USE_SHADOW_BUFFER / USE_CRTC_BLANK as safe defaults + quirks"
say ""
info "Already partly automatic in current source:"
say "           - DRM connector: auto-picked when DRM_CONN_ID=0"
say "           - DRM CRTC: auto-resolved when DRM_CRTC_ID=0"
say "           - DRM first, FBDEV fallback"
say "           - DRM preferred mode / resolution"
say "           - FBDEV width, height, pitch and mmap size via FB ioctls"
say "           - VT selection with fallbacks"
say "           - input event enumeration/hotplug in the console itself"

section "12. VALUES THAT MUST NOT BE GUESSED FROM EXISTENCE ALONE"
manual "ROTATION: sysfs may provide a hint, but visual orientation still needs validation."
manual "MARGINS: notch/cutout/safe-area cannot be reliably inferred on every recovery/kernel."
manual "COLOR_BGR: a device node existing does not prove RGB vs BGR; framebuffer bitfields/DRM format or visual validation is needed."
manual "USE_CRTC_BLANK: vendor/panel behavior differs; existence of DRM does not prove CRTC blank is safe."
manual "USE_SHADOW_BUFFER: depends on tearing/panel behavior and memory; existence checks alone are insufficient."

section "13. INFORMATIONAL SUMMARY"
if [ "$drm_count" -gt 0 ]; then
    found "DRM device node(s) exist. Recovery Console can attempt DRM first."
else
    missing "DRM device nodes. DRM backend cannot open a card unless a valid node is provided by the recovery/kernel."
fi
if [ "$fb_count" -gt 0 ]; then
    found "FBDEV node(s) exist. Legacy framebuffer is a candidate backend."
else
    missing "FBDEV nodes. Legacy framebuffer backend has no existing device node to open."
fi
if [ "$backlight_count" -gt 0 ]; then
    found "Standard backlight class exists; candidate path(s) are listed above."
else
    warn "Standard backlight class absent; use the candidate search output above and validate the correct brightness node manually."
fi
if [ -n "$first_existing_shell" ]; then
    found "Usable shell candidate: $first_existing_shell"
else
    warn "No standard shell candidate found."
fi

say ""
say "READ-ONLY PROBE COMPLETE"
say "No settings were changed."
