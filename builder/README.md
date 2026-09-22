# Channel Recovery-as-Boot Builder

This branch is dedicated to the Moto G7 Play (`channel`) flashable recovery artifact.

Normal Recovery Console binaries are built only from `Channel-Configs`. This branch consumes that profile and produces a TWRP recovery-as-boot installer.

## Base locked to the validated device test

The builder intentionally uses only:

- `twrp-installer-3.5.2_10-0-channel.zip`
- SHA-256 `2c43cee3d2fc64c7632d6f2f49567f59a563446a34b073678eda8b77cb5bd74c`

Channel uses `BOARD_USES_RECOVERY_AS_BOOT := true`. TeamWin's native installer reads `boot_a` and `boot_b`, replaces their recovery ramdisk, repacks the existing image and writes it back. The builder preserves that installer and therefore preserves the kernel/DTB/header already installed on the phone.

## Permanent integration

The ramdisk is modified according to the upstream Recovery Console README:

1. add `disabled` to the original stock `service recovery`;
2. install the binary as `/system/bin/recovery-console`;
3. define `service recovery-console /system/bin/recovery-console` in root `/init.rc`;
4. add `on boot -> start recovery-console` in root `/init.rc`;
5. preserve the original LZMA ramdisk compression;
6. preserve TeamWin `update-binary` and embedded installer `magiskboot`.

The tested base already sets recovery SELinux permissive in `early-init`.

## Build request

Edit `builder/REQUEST.env` and push it to this branch:

```sh
SOURCE_REF=Channel-Configs
ORIENTATION=all
TWRP_VERSION=3.5.2_10-0
REQUEST_ID=1
```

`ORIENTATION` accepts `all`, `portrait-0`, `landscape-90`, `portrait-180`, or `landscape-270`.

This branch owns the image-builder workflow. No Channel recovery workflow is required on `main`.

## Verified runtime behavior

The resulting permanent build was tested on-device:

```text
CONSOLE=running
TWRP=stopped
ADBD=running
```

`/system/bin/recovery-console` and `/tmp/rc.sock` were present, ADB attach worked, and `exit` from the console shell invoked the upstream cleanup fallback and started TWRP.
