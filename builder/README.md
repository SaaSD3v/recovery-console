# Albus Permanent Recovery Builder

This branch consumes `Albus-Configs` and produces flashable Albus `recovery.img` artifacts. It does not replace the normal binary CI.

## Known-good recipe

The base is regenerated from the exact read-only Albus builder snapshot and verified before integration:

- `SaaSD3v/albus-builder@a567dec13ee75bb50b0640525b20b5fc22ff6eac`
- kernel `9a7416218ae637c4120c417b31428bb0747fdfdf`
- TWRP `twrp-3.5.0_9-0-albus.img`
- TWRP SHA-256 `4c42bfee165ea99e2663284a3634135786e157bd6cc492fcbe0d9bd3430e9261`

The original LZMA ramdisk compression and legacy image layout are preserved with `magiskboot unpack -n` and `repack -n`.

## Permanent integration

The builder follows the upstream Recovery Console README method:

- stock `service recovery` receives `disabled`;
- console is installed at `/system/bin/recovery-console`;
- root `/init.rc` defines the console service;
- root `/init.rc` starts it from `on boot`.

The Albus profile keeps `DEFAULT_SHELL=/sbin/sh` because the known-good recovery exposes BusyBox there.

## Safety checks

The build fails if:

- the expected kernel/TWRP base is not reproduced;
- output exceeds the recovery partition limit;
- kernel changes during integration;
- DT/extra changes during integration;
- permanent init integration is missing;
- the final console binary is absent.

## Request

Change `builder/REQUEST.env` to select orientation. No workflow on `main` is required.
