# Channel Recovery Image Builder

Dedicated flashable recovery builder for Motorola Moto G7 Play (`channel`).

This branch does **not** serve as the normal Recovery Console binary branch. Normal device binaries and configuration live in:

- `Channel-Configs`

This branch only produces the validated **recovery-as-boot TWRP installer ZIP** with the Recovery Console permanently integrated according to the upstream `Droidspaces/recovery-console` README.

## Fixed validated base

- Device: Moto G7 Play (`channel`)
- TWRP: `twrp-installer-3.5.2_10-0-channel.zip`
- SHA-256: `2c43cee3d2fc64c7632d6f2f49567f59a563446a34b073678eda8b77cb5bd74c`
- Layout: A/B recovery-as-boot
- Console source: `Channel-Configs`
- Console path: `/system/bin/recovery-console`
- Permanent integration: stock `service recovery` disabled + `on boot -> start recovery-console`
- Original TeamWin installer logic preserved

## Choose orientation

Edit `builder/REQUEST.env`:

```sh
ORIENTATION=all
```

Allowed values:

```text
all
portrait-0
landscape-90
portrait-180
landscape-270
```

A push changing `builder/REQUEST.env` starts this branch's workflow. The repository `main` branch is not used as a dispatcher.

## Output

The output is a native TeamWin installer ZIP, for example:

```text
twrp-3.5.2_10-0-channel-recovery-console-upstream-permanent-landscape-270.zip
```

The ZIP patches the recovery ramdisk into both installed boot slots using TeamWin's original recovery-as-boot installer.

See `builder/README.md` for implementation details and `Channel-Configs/README.md` for the device profile and real-device validation results.
