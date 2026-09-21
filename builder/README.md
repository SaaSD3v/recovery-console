# Albus Recovery Image Builder

This branch belongs to **SaaSD3v/recovery-console** and does not modify `SaaSD3v/albus-builder`.

It uses the known-good Albus recovery recipe only as an external, read-only build source:

- Albus builder source snapshot: `SaaSD3v/albus-builder@a567dec13ee75bb50b0640525b20b5fc22ff6eac`
- Kernel tree: `SaaSD3v/android_kernel_motorola_msm8996`
- Kernel commit selected by that builder: `9a7416218ae637c4120c417b31428bb0747fdfdf`
- TWRP base: `twrp-3.5.0_9-0-albus.img`
- TWRP SHA-256: `4c42bfee165ea99e2663284a3634135786e157bd6cc492fcbe0d9bd3430e9261`
- Magisk used for repack/integration: `30.7`

The kernel/TWRP base is built **once**. The resulting known-good `recovery.img` is then reused for every requested Recovery Console orientation.

## Orientations

The main-repo GitHub Actions dispatcher supports:

- `all`
- `portrait-0`
- `landscape-90`
- `portrait-180`
- `landscape-270`

The Recovery Console source comes from `Albus-Configs`.

## Output

Each requested orientation produces its own final recovery image:

```text
recovery-albus-console-permanent-portrait-0.img
recovery-albus-console-permanent-landscape-90.img
recovery-albus-console-permanent-portrait-180.img
recovery-albus-console-permanent-landscape-270.img
```

Each artifact also includes:

- the matching static `recovery-console-aarch64`
- SHA-256
- build information

The base kernel, DT and TWRP layout are not changed between orientation variants. Only the Recovery Console binary/configuration inside the ramdisk differs.

The Albus builder also uses the documented **Permanent Integration** mode:

- the stock `service recovery` is patched with `disabled`;
- `service recovery-console /system/bin/recovery-console` is added;
- `on boot -> start recovery-console` starts the console automatically;
- the console service remains `disabled` only to prevent class autostart duplication;
- explicit `start recovery` remains available as the fallback to TWRP.

The integrator preserves the known-good legacy Albus image layout with `magiskboot unpack -n` / `repack -n`, preserves the detected LZMA ramdisk compression, and the workflow rejects any output whose kernel or DT differs from the known-good base.

## Albus shell exception

The permanent init integration itself follows the upstream README path and service layout exactly (`/system/bin/recovery-console`, stock recovery disabled, `on boot -> start recovery-console`). The Albus recovery ramdisk has no `/bin/sh`; it exposes `/sbin/sh -> busybox`. Therefore the Albus source keeps the device-specific shell helper using `DEFAULT_SHELL=/sbin/sh` so the upstream `stop recovery` / `start recovery` lifecycle remains functional on this recovery environment.
