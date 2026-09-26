#!/usr/bin/env python3
from pathlib import Path
import argparse
import hashlib
import struct

LIMIT = 32 * 1024 * 1024


def align(value, alignment):
    return (value + alignment - 1) // alignment * alignment


def split_boot(data):
    if data[:8] != b"ANDROID!":
        raise SystemExit("ERROR: not an Android boot image")

    kernel_size = struct.unpack_from("<I", data, 8)[0]
    ramdisk_size = struct.unpack_from("<I", data, 16)[0]
    second_size = struct.unpack_from("<I", data, 24)[0]
    page_size = struct.unpack_from("<I", data, 36)[0]
    header_version = struct.unpack_from("<I", data, 40)[0]
    recovery_dtbo_size = struct.unpack_from("<I", data, 1632)[0]
    recovery_dtbo_offset = struct.unpack_from("<Q", data, 1636)[0]
    header_size = struct.unpack_from("<I", data, 1644)[0]

    if header_version != 1 or header_size != 1648:
        raise SystemExit(
            f"ERROR: expected Android boot header v1/1648, got "
            f"v{header_version}/{header_size}"
        )

    kernel_offset = page_size
    ramdisk_offset = align(kernel_offset + kernel_size, page_size)
    second_offset = align(ramdisk_offset + ramdisk_size, page_size)
    expected_dtbo_offset = align(second_offset + second_size, page_size)

    if recovery_dtbo_size and recovery_dtbo_offset != expected_dtbo_offset:
        raise SystemExit(
            "ERROR: unexpected recovery_dtbo offset: "
            f"header={recovery_dtbo_offset} calculated={expected_dtbo_offset}"
        )

    return {
        "header": data[:page_size],
        "kernel": data[kernel_offset:kernel_offset + kernel_size],
        "ramdisk": data[ramdisk_offset:ramdisk_offset + ramdisk_size],
        "second": data[second_offset:second_offset + second_size],
        "dtbo": data[
            recovery_dtbo_offset:recovery_dtbo_offset + recovery_dtbo_size
        ],
        "tail": data[recovery_dtbo_offset + recovery_dtbo_size:],
        "page_size": page_size,
        "dtbo_size": recovery_dtbo_size,
    }


def pack(base, new_ramdisk):
    parts = split_boot(base)
    page = parts["page_size"]

    header = bytearray(parts["header"])
    struct.pack_into("<I", header, 16, len(new_ramdisk))

    new_ramdisk_offset = align(page + len(parts["kernel"]), page)
    new_second_offset = align(
        new_ramdisk_offset + len(new_ramdisk), page
    )
    new_dtbo_offset = align(
        new_second_offset + len(parts["second"]), page
    )

    if parts["dtbo_size"]:
        struct.pack_into("<Q", header, 1636, new_dtbo_offset)

    out = bytearray(header)
    out += parts["kernel"]
    out += bytes(new_ramdisk_offset - len(out))
    out += new_ramdisk
    out += bytes(new_second_offset - len(out))
    out += parts["second"]
    out += bytes(new_dtbo_offset - len(out))
    out += parts["dtbo"]
    out += parts["tail"]

    return bytes(out), parts


def main():
    ap = argparse.ArgumentParser(
        description=(
            "Replace only the external ramdisk of a Channel Android boot image "
            "while preserving kernel, second stage, recovery DTBO and tail."
        )
    )
    ap.add_argument("base_img")
    ap.add_argument("integrated_ramdisk")
    ap.add_argument("output_img")
    args = ap.parse_args()

    base_path = Path(args.base_img)
    ramdisk_path = Path(args.integrated_ramdisk)
    output_path = Path(args.output_img)

    base = base_path.read_bytes()
    new_ramdisk = ramdisk_path.read_bytes()
    output, old = pack(base, new_ramdisk)
    new = split_boot(output)

    if old["kernel"] != new["kernel"]:
        raise SystemExit("ERROR: kernel changed")
    if old["second"] != new["second"]:
        raise SystemExit("ERROR: second stage changed")
    if old["dtbo"] != new["dtbo"]:
        raise SystemExit("ERROR: recovery DTBO changed")
    if old["tail"] != new["tail"]:
        raise SystemExit("ERROR: post-DTBO tail changed")

    before_header = bytearray(old["header"])
    after_header = bytearray(new["header"])
    for off, size in ((16, 4), (1636, 8)):
        before_header[off:off + size] = bytes(size)
        after_header[off:off + size] = bytes(size)
    if before_header != after_header:
        raise SystemExit("ERROR: unexpected static boot header change")

    if len(output) > LIMIT:
        raise SystemExit(
            f"ERROR: final image is {len(output)} bytes, "
            f"{len(output) - LIMIT} bytes over 32 MiB"
        )

    output_path.write_bytes(output)
    digest = hashlib.sha256(output).hexdigest()

    print(f"base image       : {len(base)} bytes")
    print(f"old ramdisk      : {len(old['ramdisk'])} bytes")
    print(f"integrated ramdisk: {len(new_ramdisk)} bytes")
    print(f"final image      : {len(output)} bytes")
    print(f"32 MiB headroom  : {LIMIT - len(output)} bytes")
    print(f"sha256           : {digest}")
    print("kernel unchanged : YES")
    print("recovery DTBO    : YES")
    print("second/tail      : YES")


if __name__ == "__main__":
    main()
