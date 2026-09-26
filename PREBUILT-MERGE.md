# Prebuilt merge test — Channel Recovery Console + DroidSpaces/Wi-Fi

This branch is based on `Channel-DroidSpaces-Recovery-Image-Builder`.

For the size experiment, the kernel/userspace **do not need to be rebuilt**.
The proven TWRP image from `SaaSD3v/channel-kernel-build` run
`36228714501` is used as-is, and only the external recovery ramdisk is
replaced with the already-integrated Channel Recovery Console ramdisk.

The merge helper is:

```
builder/merge-prebuilt-channel.py
```

It preserves byte-for-byte:

- kernel / internal initramfs;
- second stage;
- recovery DTBO;
- post-DTBO tail.

Only the ramdisk-size / recovery-DTBO-offset header fields are adjusted.

## Measured result

Inputs used for the direct test:

- proven TWRP image: `channel-twrp-3.5.2_10-0-droidspaces-wifi-hotspot-time-sync.img`
- Recovery Console ramdisk: `ramdisk-channel-recovery-console-portrait-0.bin`
  from successful Recovery Console run `35809021077`

Result:

```text
base image        : 30310400 bytes
base ramdisk      : 13043841 bytes
console ramdisk   : 12574905 bytes
final image       : 29841408 bytes
32 MiB limit      : 33554432 bytes
remaining headroom: 3713024 bytes
```

Final SHA-256 from the direct merge:

```text
1998dbb944d7d1f7bb3e448f7c1dd03a6c1f8394d91856a7449aa71ede8832d6
```

So Recovery Console + the proven DroidSpaces kernel fixes + recovery Wi-Fi +
hotspot + static iptables + one-shot time sync fit together with about
3.54 MiB of boot-partition headroom.
