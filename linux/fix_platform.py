#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""给 Mach-O 注入 LC_BUILD_VERSION(platform=ios, minos, sdk),幂等。
lld 在 -nostartfiles 场景下偶尔不写平台指令,iOS 侧按平台判定会更稳。"""
import struct, sys

def inject(path, minos=(14, 0), sdk=(16, 5)):
    data = bytearray(open(path, "rb").read())
    magic, cputype, cpusub, ftype, ncmds, sizeofcmds = struct.unpack("<IiiIII", data[:24])
    assert magic == 0xFEEDFACF, "不是 Mach-O 64 little-endian"
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", data[off:off+8])
        if cmd in (0x8000001F, 0x25):
            print("已有平台指令 cmd=%s,跳过" % hex(cmd))
            return False
        off += size

    pv = (minos[0] << 16) | (minos[1] << 8) | 0
    sv = (sdk[0] << 16) | (sdk[1] << 8) | 0
    cmd = 0x8000001F
    cmdsize = 24
    payload = struct.pack("<IIIIII", cmd, cmdsize, 2, pv, sv, 0)  # platform 2 = PLATFORM_IOS

    insert_at = 32 + sizeofcmds
    # 安全检查:不能覆盖后面的段数据
    seg_end = None
    o = 32
    for _ in range(ncmds):
        c, s = struct.unpack("<II", data[o:o+8])
        if c == 0x19:
            nsects = struct.unpack("<I", data[o+64:o+68])[0]
            if nsects:
                so = o + 72
                best = None
                for _s in range(nsects):
                    sec_off = struct.unpack("<I", data[so+48:so+52])[0]
                    if sec_off > 0 and (best is None or sec_off < best):
                        best = sec_off
                    so += 80
                if best and seg_end is None:
                    seg_end = best
        o += s
    if seg_end is not None and insert_at + cmdsize > seg_end:
        raise SystemExit("头部空间不足,%d + %d > %d" % (insert_at, cmdsize, seg_end))

    data[insert_at:insert_at + cmdsize] = payload
    struct.pack_into("<II", data, 16, ncmds + 1, sizeofcmds + cmdsize)
    open(path, "wb").write(bytes(data))
    print("已注入 LC_BUILD_VERSION: platform=ios minos=%d.%d sdk=%d.%d" % (minos[0], minos[1], sdk[0], sdk[1]))
    return True

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "Payload/AntiAccel.app/AntiAccel"
    inject(target)
