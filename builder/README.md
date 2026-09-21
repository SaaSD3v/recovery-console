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
recovery-albus-console-portrait-0.img
recovery-albus-console-landscape-90.img
recovery-albus-console-portrait-180.img
recovery-albus-console-landscape-270.img
```

Each artifact also includes:

- the matching static `recovery-console-aarch64`
- SHA-256
- build information

The base kernel, DT and TWRP layout are not changed between orientation variants. Only the Recovery Console binary/configuration inside the ramdisk differs.

Recovery Console remains a disabled init service by default, matching the Channel integration model. TWRP remains the normal recovery UI.
