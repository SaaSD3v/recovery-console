# Albus Recovery Image Builder

Dedicated recovery-image branch for Motorola Moto Z2 Play (`albus`).

Normal Recovery Console binaries and the device configuration live in `Albus-Configs`. This branch only builds the known-good Albus recovery base and integrates Recovery Console permanently.

## Fixed known-good base

- Albus builder snapshot: `a567dec13ee75bb50b0640525b20b5fc22ff6eac`
- Kernel commit: `9a7416218ae637c4120c417b31428bb0747fdfdf`
- TWRP: `twrp-3.5.0_9-0-albus.img`
- TWRP SHA-256: `4c42bfee165ea99e2663284a3634135786e157bd6cc492fcbe0d9bd3430e9261`
- Ramdisk compression: LZMA
- Image handling: `magiskboot unpack -n` / `repack -n`
- Recovery partition limit: 21073920 bytes

The builder rejects any result whose kernel or DT/extra differs from the base.

## Choose orientation

Edit `builder/REQUEST.env` and push the change:

```sh
SOURCE_REF=Albus-Configs
ORIENTATION=all
REQUEST_ID=1
```

Allowed orientations are `all`, `portrait-0`, `landscape-90`, `portrait-180`, and `landscape-270`.

The image workflow exists only on this branch. `main` is not used as a dispatcher.

## Output

Each selected orientation produces a flashable `recovery.img` with the upstream permanent `init.rc` integration and a matching standalone console binary for inspection.
