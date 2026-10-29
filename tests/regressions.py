#!/usr/bin/env python3
import os
import random
import re
import shutil
import struct
import subprocess
import sys
import tempfile

BX = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "build/bx")
CHECKS = 0
FAILS = 0


def run(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)


def bx(*args):
    return subprocess.run([BX, *args], capture_output=True, text=True)


def check(name, cond, detail=""):
    global CHECKS, FAILS
    CHECKS += 1
    if cond:
        print(f"ok {CHECKS} - {name}")
    else:
        FAILS += 1
        print(f"not ok {CHECKS} - {name}" + (f" :: {detail}" if detail else ""))


def skip(name, why):
    print(f"skip - {name} :: {why}")


def readelf_sections(path):
    out = run(["readelf", "-SW", path]).stdout
    rows = {}
    for line in out.splitlines():
        m = re.match(
            r"\s*\[\s*(\d+)\]\s+(\S+)\s+(\S+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)",
            line,
        )
        if not m:
            continue
        rows[m.group(2)] = {
            "idx": int(m.group(1)),
            "type": m.group(3),
            "addr": int(m.group(4), 16),
            "off": int(m.group(5), 16),
            "size": int(m.group(6), 16),
        }
    return rows


def bx_sections(path):
    return bx("sections", path).stdout


def find_row(text, name):
    for line in text.splitlines():
        if len(line) >= 28 and line[6:28].strip() == name:
            return line
    return None


def find_row_prefix(text, prefix):
    for line in text.splitlines():
        if len(line) >= 28 and line[6:28].strip().startswith(prefix):
            return line
    return None


def test_layout():
    out = bx_sections("/bin/ls")
    lines = out.splitlines()
    if not lines:
        check("sections layout", False, "no output")
        return
    hdr = lines[0]
    expected = {"Name": 6, "Type": 30, "Flags": 47, "Address": 63, "Offset": 81, "Size": 99}
    h_ok = all(hdr.find(k) == v for k, v in expected.items())
    row = find_row(out, ".interp")
    ro = readelf_sections("/bin/ls").get(".interp")
    row_ok = bool(row and ro)
    if row_ok:
        row_ok = (
            row[30:38] == "PROGBITS"
            and row[47] == "A"
            and row[63:79] == f"{ro['addr']:016x}"
            and row[81:97] == f"{ro['off']:016x}"
            and row[99:115] == f"{ro['size']:016x}"
        )
    check(
        "sections header and .interp row align",
        h_ok and row_ok,
        f"hdr={[hdr.find(k) for k in expected]} row={row[:120] if row else None!r}",
    )


def test_five_flags(tmp):
    p = os.path.join(tmp, "flags5")
    shutil.copyfile("/bin/ls", p)
    ro = readelf_sections(p).get(".rodata")
    if ro is None:
        check("five flags fixture", False, ".rodata missing")
        return
    with open(p, "r+b") as f:
        data = bytearray(f.read())
        shoff = struct.unpack_from("<Q", data, 40)[0]
        off = shoff + ro["idx"] * 64 + 8
        struct.pack_into("<Q", data, off, 0x2 | 0x4 | 0x10 | 0x20 | 0x40)
        f.seek(0)
        f.write(data)
    out = bx_sections(p)
    row = find_row(out, ".rodata")
    ok = bool(row)
    if ok:
        flags = row[47:61].strip()
        ok = (
            flags == "AXMSI"
            and row[63:79] == f"{ro['addr']:016x}"
            and row[81:97] == f"{ro['off']:016x}"
        )
    check("five flags keep the address column", ok, row[:130] if row else "row missing")


def test_long_name(tmp):
    p = os.path.join(tmp, "longname")
    longname = ".averylongsectionnamethatoverflows"
    shutil.copyfile("/bin/ls", p)
    r = run(["objcopy", "--rename-section", f".rodata={longname}", p])
    if r.returncode != 0:
        check("objcopy long name", False, r.stderr.strip()[:100])
        return
    out = bx_sections(p)
    lines = out.splitlines()
    hdr = lines[0] if lines else ""
    name_col = hdr.find("Name")
    type_col = hdr.find("Type")
    addr_col = hdr.find("Address")
    off_col = hdr.find("Offset")
    row = find_row_prefix(out, ".averylong")
    ro = readelf_sections(p).get(longname)
    ok = bool(row and ro and name_col >= 0 and type_col > name_col and addr_col > 0 and off_col > 0)
    if ok:
        name_width = type_col - name_col - 2
        ok = (
            name_width == len(longname)
            and row[name_col:name_col + len(longname)] == longname
            and ".." not in row[name_col:type_col]
            and row[addr_col:addr_col + 16] == f"{ro['addr']:016x}"
            and row[off_col:off_col + 16] == f"{ro['off']:016x}"
        )
    check("long names keep full text and alignment", ok, row[:160] if row else "row missing")


def test_ansi_name(tmp):
    p = os.path.join(tmp, "escname")
    shutil.copyfile("/bin/ls", p)
    with open(p, "r+b") as f:
        data = f.read()
        old = b".note.ABI-tag\x00"
        i = data.find(old)
        if i < 0:
            check("ANSI fixture name present", False, "name not found")
            return
        f.seek(i)
        f.write(b"\x1b[31mX\n\x00")
    r = subprocess.run([BX, "sections", p], capture_output=True)
    count = int(run(["readelf", "-h", p]).stdout.split("Number of section headers:")[1].split()[0])
    check(
        "ANSI/newline in section name sanitized",
        r.returncode == 0 and b"\x1b" not in r.stdout,
        f"rc={r.returncode} first={r.stdout[:80]!r}",
    )
    check(
        "sanitized name does not add lines",
        len(r.stdout.splitlines()) == count + (1 if count else 0),
        f"lines={len(r.stdout.splitlines())} sections={count}",
    )


def test_exclude_flag(tmp):
    p = os.path.join(tmp, "flagE")
    shutil.copyfile("/bin/ls", p)
    with open(p, "r+b") as f:
        data = bytearray(f.read())
        shoff = struct.unpack_from("<Q", data, 40)[0]
        ro = readelf_sections(p).get(".data")
        if ro is None:
            check("SHF_EXCLUDE fixture section", False, ".data missing")
            return
        off = shoff + ro["idx"] * 64 + 8
        struct.pack_into("<Q", data, off, 0x80000001)
        f.seek(0)
        f.write(data)
    out = bx_sections(p)
    row = find_row(out, ".data")
    ok = False
    if row:
        flags = row[47:61].strip()
        ok = "W" in flags and "E" in flags and "?" not in flags
    check("SHF_EXCLUDE (E) displayed", ok, row[:130] if row else "row missing")

    p2 = os.path.join(tmp, "flagUnknown")
    shutil.copyfile("/bin/ls", p2)
    with open(p2, "r+b") as f:
        data = bytearray(f.read())
        shoff = struct.unpack_from("<Q", data, 40)[0]
        off = shoff + ro["idx"] * 64 + 8
        struct.pack_into("<Q", data, off, 0x1000000)
        f.seek(0)
        f.write(data)
    out2 = bx_sections(p2)
    row2 = find_row(out2, ".data")
    ok2 = bool(row2)
    if ok2:
        flags2 = row2[47:61].strip()
        ok2 = "?" in flags2 and row2[63:79] == f"{ro['addr']:016x}"
    check("unknown flag bits marked", ok2, row2[:130] if row2 else "row missing")


def test_libc_sections():
    candidates = [
        "/usr/lib/x86_64-linux-gnu/libc.so.6",
        "/lib/x86_64-linux-gnu/libc.so.6",
    ]
    libc = next((p for p in candidates if os.path.exists(p)), None)
    if not libc:
        skip("libc sections match readelf", "libc not found")
        return
    lines = bx_sections(libc).splitlines()
    if not lines:
        check("libc sections match readelf", False, "no output")
        return
    hdr = lines[0]
    nc = hdr.find("Name")
    tc = hdr.find("Type")
    ac = hdr.find("Address")
    oc = hdr.find("Offset")
    sc = hdr.find("Size")
    brows = {}
    for line in lines[1:]:
        m = re.match(r"^\[\s*(\d+)\] ", line)
        if not m:
            continue
        idx = int(m.group(1))
        brows[idx] = (
            line[nc:tc - 2].strip(),
            int(line[ac:ac + 16], 16),
            int(line[oc:oc + 16], 16),
            int(line[sc:sc + 16], 16),
        )
    rrows = {}
    for line in run(["readelf", "-SW", libc]).stdout.splitlines():
        m = re.match(
            r"\s*\[\s*(\d+)\]\s+(\S+)\s+(\S+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)",
            line,
        )
        if m:
            rrows[int(m.group(1))] = (
                m.group(2),
                int(m.group(4), 16),
                int(m.group(5), 16),
                int(m.group(6), 16),
            )
    bad = []
    for idx in sorted(set(brows) | set(rrows)):
        b = brows.get(idx)
        r = rrows.get(idx)
        if b is None or r is None:
            bad.append((idx, "missing", b, r))
        elif b[1:] != r[1:]:
            bad.append((idx, "fields", b, r))
        elif idx != 0 and b[0] != r[0]:
            bad.append((idx, "name", b, r))
    check(
        f"libc: {len(brows)} sections match readelf",
        len(brows) == len(rrows) and not bad,
        str(bad[:3]),
    )


def test_gnu_types_and_retain():
    candidates = [
        "/usr/lib/x86_64-linux-gnu/libc.so.6",
        "/lib/x86_64-linux-gnu/libc.so.6",
    ]
    libc = next((p for p in candidates if os.path.exists(p)), None)
    if not libc:
        skip("GNU section types and retain flag", "libc not found")
        return
    out = bx_sections(libc)
    lines = out.splitlines()
    hdr = lines[0] if lines else ""
    type_col = hdr.find("Type")
    flags_col = hdr.find("Flags")
    rows = {
        n: find_row(out, n)
        for n in [
            "__libc_subfreeres",
            "__libc_atexit",
            ".gnu.version_d",
            ".gnu.version_r",
            ".gnu.version",
        ]
    }
    retain = [
        rows[n][flags_col:flags_col + 14].strip()
        for n in ("__libc_subfreeres", "__libc_atexit")
        if rows[n]
    ]
    if retain:
        check("SHF_GNU_RETAIN (R) displayed", any("R" in f for f in retain), f"flags={retain}")
    else:
        skip("SHF_GNU_RETAIN (R) displayed", "sections missing")
    types = {
        ".gnu.version_d": rows[".gnu.version_d"][type_col:type_col + 15].strip() if rows[".gnu.version_d"] else None,
        ".gnu.version_r": rows[".gnu.version_r"][type_col:type_col + 15].strip() if rows[".gnu.version_r"] else None,
        ".gnu.version": rows[".gnu.version"][type_col:type_col + 15].strip() if rows[".gnu.version"] else None,
    }
    if all(types.values()):
        check(
            "GNU version types match readelf naming",
            types[".gnu.version_d"] == "VERDEF"
            and types[".gnu.version_r"] == "VERNEED"
            and types[".gnu.version"] == "VERSYM",
            f"types={types}",
        )
    else:
        skip("GNU version types match readelf naming", f"missing sections: {types}")


def test_cli():
    r = bx("hex", "--offset=16", "-n4", "/bin/ls")
    check("--offset=value accepted", r.returncode == 0 and "0000000000000010" in r.stdout, r.stderr)
    r = bx("hex", "-o16", "-n4", "/bin/ls")
    check("-oVALUE accepted", r.returncode == 0, r.stderr)
    r = bx("hex", "-n4", "/bin/ls", "--")
    check("trailing -- accepted", r.returncode == 0, r.stderr)
    for args in [
        ("info", "--", "/bin/ls"),
        ("info", "/bin/ls", "--"),
        ("sections", "--", "/bin/ls"),
        ("sections", "/bin/ls", "--"),
    ]:
        r = bx(*args)
        check("double dash: " + " ".join(args), r.returncode == 0, r.stderr)
    r = bx("hex", "-o", "9223372036854775808", "-n", "1", "/bin/ls")
    check("decimal 2^63 accepted", r.returncode == 0, r.stderr)
    r = bx("hex", "-o", "18446744073709551615", "-n", "1", "/bin/ls")
    check("decimal u64 max accepted", r.returncode == 0, r.stderr)
    r = bx("hex", "-o", "18446744073709551616", "-n", "1", "/bin/ls")
    check("decimal overflow rejected", r.returncode == 2, r.stderr)
    r = subprocess.run([BX, "hex", "-"], input="hello", capture_output=True, text=True)
    check("hex - rejected clearly", r.returncode == 1 and "stdin" in r.stderr, r.stderr)
    r = bx("hex", "/dev/null")
    check("char device rejected", r.returncode == 1 and "regular" in r.stderr, r.stderr)
    r = bx("info", "/dev/null")
    check("info on char device rejected", r.returncode == 1 and "regular" in r.stderr, r.stderr)
    if os.path.exists("/proc/self/cmdline"):
        r = bx("hex", "/proc/self/cmdline")
        check(
            "zero-size proc file rejected",
            r.returncode == 1 and "not reported" in r.stderr,
            r.stderr,
        )


def test_full_hex(tmp):
    p = os.path.join(tmp, "hex257.bin")
    data = bytes((i * 37 + 11) & 0xFF for i in range(257))
    with open(p, "wb") as f:
        f.write(data)
    r = bx("hex", p)
    parsed = {}
    for line in r.stdout.splitlines():
        m = re.match(r"^([0-9a-f]{16})  (.*)$", line)
        if not m:
            continue
        base = int(m.group(1), 16)
        hexpart = m.group(2).split("|")[0]
        for i, tok in enumerate(hexpart.split()):
            parsed[base + i] = int(tok, 16)
    ok = r.returncode == 0 and len(parsed) == len(data) and all(parsed.get(i) == b for i, b in enumerate(data))
    check("full-file hex matches every byte", ok, f"rc={r.returncode} parsed={len(parsed)} want={len(data)}")


def test_extended(tmp):
    raw = bytearray(open("/bin/ls", "rb").read())
    shoff = struct.unpack_from("<Q", raw, 40)[0]
    shnum = struct.unpack_from("<H", raw, 60)[0]
    shstr = struct.unpack_from("<H", raw, 62)[0]
    phnum = struct.unpack_from("<H", raw, 56)[0]

    p = os.path.join(tmp, "ext_shnum")
    d = bytearray(raw)
    struct.pack_into("<H", d, 60, 0)
    struct.pack_into("<Q", d, shoff + 32, shnum)
    open(p, "wb").write(d)
    r = bx("info", p)
    check("extended shnum count", r.returncode == 0 and f"Sections:  {shnum}" in r.stdout, r.stdout[:120])
    r = bx("sections", p)
    check("extended shnum names", r.returncode == 0 and ".interp" in r.stdout, r.stderr)

    p = os.path.join(tmp, "ext_shstr")
    d = bytearray(raw)
    struct.pack_into("<H", d, 62, 0xFFFF)
    struct.pack_into("<I", d, shoff + 40, shstr)
    open(p, "wb").write(d)
    r = bx("sections", p)
    check("extended shstrndx names", r.returncode == 0 and ".interp" in r.stdout, r.stderr)

    p = os.path.join(tmp, "ext_phnum")
    d = bytearray(raw)
    struct.pack_into("<H", d, 56, 0xFFFF)
    struct.pack_into("<I", d, shoff + 44, phnum)
    open(p, "wb").write(d)
    r = bx("info", p)
    check("extended phnum count", r.returncode == 0 and f"Segments:  {phnum}" in r.stdout, r.stdout[:120])


def test_fifo(tmp):
    p = os.path.join(tmp, "writerless.fifo")
    os.mkfifo(p)
    for cmd in ("hex", "info"):
        try:
            r = subprocess.run([BX, cmd, p], capture_output=True, text=True, timeout=2)
        except subprocess.TimeoutExpired:
            check(f"{cmd} rejects a writerless FIFO", False, "timed out")
            continue
        check(
            f"{cmd} rejects a writerless FIFO",
            r.returncode == 1 and "not a regular file" in r.stderr,
            f"rc={r.returncode} err={r.stderr.strip()[:80]}",
        )


def test_write_errors():
    if not os.path.exists("/dev/full"):
        skip("stdout write errors exit 1", "/dev/full missing")
        return
    for args in (("info", "/bin/ls"), ("hex", "-n", "64", "/bin/ls")):
        with open("/dev/full", "wb") as f:
            r = subprocess.run([BX, *args], stdout=f, stderr=subprocess.PIPE, text=True)
        check(
            f"stdout write error exits 1: {args[0]}",
            r.returncode == 1,
            f"rc={r.returncode} err={r.stderr.strip()[:80]}",
        )


def test_many_sections(tmp):
    n = 1001
    shstr = bytearray(b"\x00")
    offsets = {}
    for i in range(1, n):
        offsets[i] = len(shstr)
        shstr += f".s{i}\x00".encode()
    shoff = 64
    shstr_off = shoff + n * 64
    shdrs = bytearray(64)
    for i in range(1, n - 1):
        shdrs += struct.pack("<IIQQQQIIQQ", offsets[i], 1, 0, 0, 0, 0, 0, 0, 1, 0)
    shdrs += struct.pack("<IIQQQQIIQQ", offsets[n - 1], 3, 0, 0, shstr_off, len(shstr), 0, 0, 1, 0)
    ehdr = struct.pack(
        "<16sHHIQQQIHHHHHH",
        b"\x7fELF\x02\x01\x01\x00" + b"\x00" * 8,
        1,
        62,
        1,
        0,
        0,
        shoff,
        0,
        64,
        0,
        0,
        64,
        n,
        n - 1,
    )
    p = os.path.join(tmp, "many.elf")
    with open(p, "wb") as f:
        f.write(ehdr)
        f.write(shdrs)
        f.write(shstr)
    r = bx("info", p)
    check(
        "1001 sections: info count",
        r.returncode == 0 and "Sections:  1001" in r.stdout,
        r.stdout[:120],
    )
    r = bx("sections", p)
    lines = r.stdout.splitlines()
    hdr = lines[0] if lines else ""
    name_col = hdr.find("Name")
    type_col = hdr.find("Type")
    addr_col = hdr.find("Address")
    off_col = hdr.find("Offset")
    size_col = hdr.find("Size")
    row = next((l for l in lines if ".s1000" in l), "")
    ok = r.returncode == 0 and len(lines) == n + 1 and bool(row)
    if ok:
        ok = (
            name_col > 0
            and type_col > name_col
            and row.find(".s1000") == name_col
            and row[addr_col:addr_col + 16] == "0000000000000000"
            and row[off_col:off_col + 16] == f"{shstr_off:016x}"
            and row[size_col:size_col + 16] == f"{len(shstr):016x}"
        )
    check("1001 sections: index and columns align", ok, row[:150] if row else "row missing")


def test_huge_sections(tmp):
    n = 100001
    shstr = bytearray(b"\x00")
    offsets = {}
    for i in range(1, n):
        offsets[i] = len(shstr)
        shstr += f".s{i}\x00".encode()
    shoff = 64
    shstr_off = shoff + n * 64
    shdrs = bytearray(64)
    struct.pack_into("<Q", shdrs, 32, n)
    struct.pack_into("<I", shdrs, 40, n - 1)
    for i in range(1, n - 1):
        shdrs += struct.pack("<IIQQQQIIQQ", offsets[i], 1, 0, 0, 0, 0, 0, 0, 1, 0)
    shdrs += struct.pack("<IIQQQQIIQQ", offsets[n - 1], 3, 0, 0, shstr_off, len(shstr), 0, 0, 1, 0)
    ehdr = struct.pack(
        "<16sHHIQQQIHHHHHH",
        b"\x7fELF\x02\x01\x01\x00" + b"\x00" * 8,
        1,
        62,
        1,
        0,
        0,
        shoff,
        0,
        64,
        0,
        0,
        64,
        0,
        0xFFFF,
    )
    p = os.path.join(tmp, "huge.elf")
    with open(p, "wb") as f:
        f.write(ehdr)
        f.write(shdrs)
        f.write(shstr)
    r = bx("info", p)
    check(
        "100001 sections: info count",
        r.returncode == 0 and "Sections:  100001" in r.stdout,
        r.stdout[:120],
    )
    try:
        r = subprocess.run([BX, "sections", p], capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        check("100001 sections: no hang and aligned", False, "timed out")
        return
    lines = r.stdout.splitlines()
    hdr = lines[0] if lines else ""
    name_col = hdr.find("Name")
    addr_col = hdr.find("Address")
    off_col = hdr.find("Offset")
    size_col = hdr.find("Size")
    row = next((l for l in lines if ".s100000" in l), "")
    ok = r.returncode == 0 and len(lines) == n + 1 and bool(row)
    if ok:
        ok = (
            name_col > 0
            and row.find(".s100000") == name_col
            and row[addr_col:addr_col + 16] == "0000000000000000"
            and row[off_col:off_col + 16] == f"{shstr_off:016x}"
            and row[size_col:size_col + 16] == f"{len(shstr):016x}"
        )
    check("100001 sections: no hang and aligned", ok, row[:150] if row else "row missing")


def test_fuzz(tmp):
    raw = bytearray(open("/bin/ls", "rb").read())
    size = len(raw)
    fields = [
        (16, "<H"),
        (18, "<H"),
        (20, "<I"),
        (32, "<Q"),
        (40, "<Q"),
        (52, "<H"),
        (54, "<H"),
        (56, "<H"),
        (58, "<H"),
        (60, "<H"),
        (62, "<H"),
    ]
    vals = [0, 1, 2, 3, 0xFFFF, 0x100000, size - 1, size, size + 1, 0xDEADBEEF]
    rng = random.Random(20261029)
    bad = []
    p = os.path.join(tmp, "fuzz.elf")
    for i in range(120):
        data = bytearray(raw)
        for _ in range(rng.randint(1, 3)):
            off, fmt = rng.choice(fields)
            v = rng.choice(vals)
            if rng.random() < 0.3:
                v = rng.getrandbits(struct.calcsize(fmt) * 8)
            mask = (1 << (8 * struct.calcsize(fmt))) - 1
            try:
                struct.pack_into(fmt, data, off, v & mask)
            except struct.error:
                pass
        with open(p, "wb") as f:
            f.write(data)
        for cmd in ("info", "sections"):
            try:
                r = subprocess.run([BX, cmd, p], capture_output=True, text=True, timeout=2)
            except subprocess.TimeoutExpired:
                bad.append((i, cmd, "timeout"))
                continue
            if r.returncode < 0 or r.returncode not in (0, 1):
                bad.append((i, cmd, r.returncode, r.stderr.strip()[:60]))
    check("120 mutated ELF headers: no crashes or hangs", not bad, str(bad[:3]))


def test_install(tmp):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    installer = os.path.join(root, "install.sh")
    dest = os.path.join(tmp, "installed")
    env = {**os.environ, "PREFIX": dest}
    r = subprocess.run(["bash", installer], capture_output=True, text=True, env=env)
    binp = os.path.join(dest, "bin", "bx")
    ok = r.returncode == 0 and os.path.exists(binp)
    if ok:
        v = subprocess.run([binp, "--version"], capture_output=True, text=True)
        ok = (
            v.returncode == 0
            and os.path.getsize(binp) <= 15000
            and os.path.exists(os.path.join(dest, "share", "man", "man1", "bx.1"))
        )
    check("installer strips binary and installs man page", ok, r.stderr.strip()[:100])

    dest2 = os.path.join(tmp, "installed-unstripped")
    env2 = {**os.environ, "PREFIX": dest2, "STRIP": "0"}
    r2 = subprocess.run(["bash", installer], capture_output=True, text=True, env=env2)
    binp2 = os.path.join(dest2, "bin", "bx")
    ok2 = (
        r2.returncode == 0
        and os.path.exists(binp2)
        and os.path.getsize(binp2) == os.path.getsize(BX)
    )
    check("installer STRIP=0 keeps symbols", ok2, r2.stderr.strip()[:100])


def main():
    if not os.path.exists(BX):
        print(f"missing binary: {BX}", file=sys.stderr)
        return 1
    if shutil.which("readelf") is None or shutil.which("objcopy") is None:
        print("readelf and objcopy are required", file=sys.stderr)
        return 1
    tmp = tempfile.mkdtemp(prefix="bx-regress-")
    try:
        test_layout()
        test_five_flags(tmp)
        test_long_name(tmp)
        test_ansi_name(tmp)
        test_exclude_flag(tmp)
        test_gnu_types_and_retain()
        test_libc_sections()
        test_cli()
        test_full_hex(tmp)
        test_extended(tmp)
        test_fifo(tmp)
        test_write_errors()
        test_many_sections(tmp)
        test_huge_sections(tmp)
        test_fuzz(tmp)
        test_install(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if CHECKS == 0:
        print("no regression checks ran", file=sys.stderr)
        return 1
    print(f"regressions: checks={CHECKS} fail={FAILS}")
    return 0 if FAILS == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
