import argparse, struct, zipfile, io, sys, json, shutil, os
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PKG_OF = {
    "MonetWeChat": "monet.com.tencent.mm",
    "MonetWeChatBubblePro": "monet.bubblepro.com.tencent.mm",
    "MonetWeChatClassicBubble": "monet.classicbubble.com.tencent.mm",
    "MonetWeChatMultiSceneCorners": "monet.multiscenecorners.com.tencent.mm",
    "MonetWeChatSolidTab": "monet.solidtab.com.tencent.mm",
}


def _path(value):
    return Path(value).expanduser().resolve()


def _module_files(repo):
    files = repo / "files"
    return files if files.is_dir() else repo

def parse_pool(buf, chunk_off):
    """parse a ResStringPool chunk at chunk_off, return (header_size, string_count, flags,
       offsets list, data_off, strings list, style_start, style_size, raw)"""
    t, hsize, size = struct.unpack_from("<HHI", buf, chunk_off)
    assert t == 0x0001, hex(t)
    string_count, style_count, flags, strings_start, styles_start = struct.unpack_from("<IIIII", buf, chunk_off + 8)
    utf8 = bool(flags & 0x100)
    offsets = list(struct.unpack_from(f"<{string_count}I", buf, chunk_off + hsize))
    strings = []
    base = chunk_off + strings_start
    for off in offsets:
        p = base + off
        if utf8:
            # u16len (1-2 bytes), u8len (1-2 bytes), bytes, 0x00
            u16len, p2 = read_len8(buf, p)
            u8len, p3 = read_len8(buf, p2)
            s = buf[p3:p3 + u8len].decode("utf-8", "replace")
            strings.append(s)
        else:
            u16len, p2 = read_len16(buf, p)
            s = buf[p2:p2 + u16len * 2].decode("utf-16-le", "replace")
            strings.append(s)
    return dict(type=t, header_size=hsize, size=size, string_count=string_count,
                style_count=style_count, flags=flags, strings_start=strings_start,
                styles_start=styles_start, offsets=offsets, strings=strings, utf8=utf8)

def read_len8(buf, p):
    b = buf[p]
    if b & 0x80:
        return ((b & 0x7F) << 8) | buf[p + 1], p + 2
    return b, p + 1

def read_len16(buf, p):
    v = struct.unpack_from("<H", buf, p)[0]
    if v & 0x8000:
        return ((v & 0x7FFF) << 16) | struct.unpack_from("<H", buf, p + 2)[0], p + 4
    return v, p + 2

def enc_len8(n):
    if n < 0x80:
        return bytes([n])
    return bytes([(n >> 8) | 0x80, n & 0xFF])

def build_pool(pool, replacements):
    """rebuild pool chunk bytes with replaced strings (index -> new str)"""
    strings = list(pool["strings"])
    for idx, new in replacements.items():
        strings[idx] = new
    utf8 = pool["utf8"]
    header_size = 28
    n = len(strings)
    offs = []
    data = bytearray()
    for s in strings:
        offs.append(len(data))
        if utf8:
            b = s.encode("utf-8")
            data += enc_len8(len(s)) + enc_len8(len(b)) + b + b"\x00"
        else:
            data += struct.pack("<H", len(s)) + s.encode("utf-16-le") + b"\x00\x00"
    while len(data) % 4:
        data += b"\x00"
    strings_start = header_size + 4 * n
    # style chunk: keep raw if present (we assume none for key pools)
    style_size = 0
    styles_start = 0
    if pool["style_count"]:
        # preserve original style region bytes
        orig_style_off = pool["chunk_off"] + pool["styles_start"] if False else None
    size = strings_start + len(data)
    head = struct.pack("<HHIIIIII", 0x0001, header_size, size, n, pool["style_count"],
                       pool["flags"], strings_start, styles_start)
    out = head + struct.pack(f"<{n}I", *offs) + bytes(data)
    return out

def patch_arsc(arsc_bytes, key_renames_by_pkg, allow_existing_strings=False):
    """key_renames_by_pkg: {package_name: {old_name: new_name}} — renames key strings"""
    buf = bytearray(arsc_bytes)
    # table header
    _, thsize, tsize = struct.unpack_from("<HHI", buf, 0)
    pkg_count = struct.unpack_from("<I", buf, 8)[0]
    off = thsize
    total_delta = 0
    patched_pkgs = []
    while off < len(buf):
        ct, chs, csz = struct.unpack_from("<HHI", buf, off)
        if ct == 0x0200:  # package
            pkg_id, = struct.unpack_from("<I", buf, off + 8)
            name = buf[off + 12:off + 12 + 256].decode("utf-16-le", "replace").split("\x00")[0]
            type_strings_off, last_pub_type, key_strings_off, last_pub_key = struct.unpack_from("<IIII", buf, off + 268)
            renames = key_renames_by_pkg.get(name)
            if renames:
                koff = off + key_strings_off
                pool = parse_pool(buf, koff)
                assert pool["style_count"] == 0, "style span in key pool not supported"
                pool["chunk_off"] = koff
                idx = {s: i for i, s in enumerate(pool["strings"])}
                repl = {}
                for old, new in renames.items():
                    if old not in idx:
                        raise SystemExit(f"[{name}] key '{old}' not found in pool")
                    if new in idx and not allow_existing_strings:
                        raise SystemExit(f"[{name}] key '{new}' already exists")
                    repl[idx[old]] = new
                new_pool = build_pool(pool, repl)
                old_size = struct.unpack_from("<I", buf, koff + 4)[0]
                delta = len(new_pool) - old_size
                buf[koff:koff + old_size] = new_pool
                # update package chunk size and table size
                struct.pack_into("<I", buf, off + 4, csz + delta)
                patched_pkgs.append((name, len(renames), delta))
                total_delta += delta
                off += csz + delta
            else:
                off += csz
        else:
            off += csz
    # fix table size
    struct.pack_into("<I", buf, 4, len(buf))
    return bytes(buf), patched_pkgs, total_delta


def patch_arsc_typed(arsc_bytes, renames_by_pkg):
    """Rename type/name entries without changing other users of a shared key.

    Append keys and update entry indices; a color and drawable may legitimately
    share the original key string. Resource IDs and internal references stay fixed.
    """
    buf = bytearray(arsc_bytes)
    off = struct.unpack_from('<H', buf, 2)[0]
    report = []
    while off < len(buf):
        kind, header, size = struct.unpack_from('<HHI', buf, off)
        if kind != 0x200:
            off += size
            continue
        pkg = buf[off + 12:off + 268].decode('utf-16-le').split('\0', 1)[0]
        renames = renames_by_pkg.get(pkg, {})
        if not renames:
            off += size
            continue
        type_off, _, key_off, _ = struct.unpack_from('<IIII', buf, off + 268)
        types = parse_pool(buf, off + type_off)['strings']
        pool = parse_pool(buf, off + key_off)
        if pool['style_count']:
            raise ValueError('Styled resource key pool is unsupported')
        keys = list(pool['strings'])
        index = {s: i for i, s in enumerate(keys)}
        found = set()
        final_names = {}
        pos = off + header
        while pos < off + size:
            ck, hs, cs = struct.unpack_from('<HHI', buf, pos)
            if ck == 0x201:
                type_id, flags = buf[pos + 8], buf[pos + 9]
                count, start = struct.unpack_from('<II', buf, pos + 12)
                for i in range(count):
                    if flags & 1:  # sparse index/offset16 pairs
                        entry_id, value = struct.unpack_from('<HH', buf, pos + hs + i * 4)
                        value *= 4
                    elif flags & 2:  # dense offset16 table
                        entry_id = i
                        value = struct.unpack_from('<H', buf, pos + hs + i * 2)[0]
                        if value == 0xffff:
                            continue
                        value *= 4
                    else:
                        entry_id = i
                        value = struct.unpack_from('<I', buf, pos + hs + i * 4)[0]
                        if value == 0xffffffff:
                            continue
                    entry = pos + start + value
                    entry_flags = struct.unpack_from('<H', buf, entry + 2)[0]
                    if entry_flags & 8:
                        raise ValueError('Compact resource entries are unsupported')
                    old_key = struct.unpack_from('<I', buf, entry + 4)[0]
                    old = f'{types[type_id - 1]}/{keys[old_key]}'
                    new = renames.get(old, old)
                    if new.split('/', 1)[0] != types[type_id - 1]:
                        raise ValueError(f'Resource type changed: {old} -> {new}')
                    resource_id = (type_id, entry_id)
                    if new in final_names and final_names[new] != resource_id:
                        raise ValueError(f'Duplicate mapped resource: {new}')
                    final_names[new] = resource_id
                    if old in renames:
                        found.add(old)
                        name = new.split('/', 1)[1]
                        if name not in index:
                            index[name] = len(keys)
                            keys.append(name)
                        struct.pack_into('<I', buf, entry + 4, index[name])
            pos += cs
        missing = set(renames) - found
        if missing:
            raise ValueError(f'Unknown source entries: {sorted(missing)}')
        pool['strings'] = keys
        pool['flags'] &= ~1  # appended keys are not sorted
        new_pool = build_pool(pool, {})
        delta = len(new_pool) - pool['size']
        buf[off + key_off:off + key_off + pool['size']] = new_pool
        if type_off > key_off:
            struct.pack_into('<I', buf, off + 268, type_off + delta)
        struct.pack_into('<I', buf, off + 4, size + delta)
        report.append((pkg, len(found), delta))
        off += size + delta
    struct.pack_into('<I', buf, 4, len(buf))
    return bytes(buf), report, len(buf) - len(arsc_bytes)


def patch_apk(src, dst, renames_by_pkg, allow_existing_strings=False, typed=False):
    src = Path(src)
    dst = Path(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    zin = zipfile.ZipFile(src)
    arsc = zin.read("resources.arsc")
    if typed:
        new_arsc, report, delta = patch_arsc_typed(arsc, renames_by_pkg)
    else:
        new_arsc, report, delta = patch_arsc(
            arsc, renames_by_pkg, allow_existing_strings=allow_existing_strings
        )
    zout = zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED)
    for info in zin.infolist():
        fn = info.filename
        if fn.upper().startswith("META-INF/") and fn.upper().endswith((".RSA", ".DSA", ".EC", ".SF", ".MF")):
            continue  # strip stale signatures
        if fn == "resources.arsc":
            zout.writestr(fn, new_arsc, compress_type=zipfile.ZIP_DEFLATED)
        else:
            zout.writestr(info, zin.read(fn), compress_type=zipfile.ZIP_DEFLATED)
    zout.close()
    zin.close()
    return report

def _parse_args():
    module_default = os.environ.get("MODULE_SOURCE") or os.environ.get("MODULE_SRC") \
        or os.environ.get("MODULE_REPO")
    output_default = os.environ.get("OUTPUT_DIR") or os.environ.get("PATCHED_DIR") \
        or os.environ.get("MODULE_OUT") or str(ROOT / "patched")
    parser = argparse.ArgumentParser(description="Patch resource key names in overlay APKs.")
    parser.add_argument("--final-map", default=os.environ.get("FINAL_MAP", str(ROOT / "final_map.json")),
                        help="Final mapping JSON generated by wx_execute.py.")
    parser.add_argument("--module-source", "--module-repo", "--module-src", dest="module_repo", default=module_default,
                        help="Pristine upstream module (or its files/ directory; set MODULE_SOURCE).")
    parser.add_argument("--output-dir", "--patched-dir", "--module-out", dest="output_dir",
                        default=output_default, help="Directory for patched APKs (or set OUTPUT_DIR).")
    args = parser.parse_args()
    final_path = _path(args.final_map)
    if not args.module_repo:
        parser.error("--module-source or MODULE_SOURCE is required")
    module_repo = _path(args.module_repo)
    module_files = _module_files(module_repo)
    output_dir = _path(args.output_dir)
    if not final_path.is_file():
        parser.error(f"Final mapping not found: {final_path}")
    if not module_files.is_dir():
        parser.error(f"Module repository/files directory not found: {module_files}")
    try:
        if output_dir.exists() and module_files.samefile(output_dir):
            parser.error("--output-dir must not be the module files directory")
    except OSError:
        pass
    output_dir.mkdir(parents=True, exist_ok=True)
    return final_path, module_files, output_dir


if __name__ == "__main__":
    final_path, module_files, outdir = _parse_args()
    final = json.loads(final_path.read_text(encoding="utf8"))["final"]
    for ov, renames in final.items():
        if ov not in PKG_OF:
            raise SystemExit(f"unknown overlay in final map: {ov}")
        pkg = PKG_OF[ov]
        m = {}
        for old, new in renames.items():
            ot, on = old.split("/", 1)
            nt, nn = new.split("/", 1)
            assert ot == nt, f"type changed {old}->{new}"
            m[on] = nn
        if not m:
            continue
        src = module_files / f"{ov}.apk"
        if not src.is_file():
            raise SystemExit(f"module APK not found: {src}")
        dst = outdir / f"{ov}.apk"
        rep = patch_apk(src, dst, {pkg: m})
        print(ov, "->", dst, "patched:", rep)
