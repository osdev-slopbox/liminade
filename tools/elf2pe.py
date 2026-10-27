#!/usr/bin/env python3
"""Repackage a freestanding ELF64 executable as a PE32+ UEFI application.

nixpkgs contains no Ada compiler that targets PE/COFF, so liminade is built
as a freestanding ELF with native GNAT and converted to the UEFI image format
here.

Mapping rules:
  * every PT_LOAD segment becomes one PE section (flags -> section perms)
  * ImageBase is the lowest PT_LOAD virtual address (page aligned)
  * AddressOfEntryPoint is the ELF symbol ``efi64_entry`` (the MS x64 -> SysV
    ABI shim that the firmware must call first)
  * Subsystem 10 (EFI application), Machine 0x8664
  * the resulting image is *not* relocatable (no .reloc directory); the
    firmware loads it at ImageBase, which it does when that range is free
    (true under OVMF/QEMU)

Usage:  elf2pe.py <input.elf> <output.efi> [--verbose]
"""

import argparse
import struct
import sys

# --- ELF constants ---------------------------------------------------------

PT_LOAD = 1
PF_X, PF_W, PF_R = 1, 2, 4

SHT_SYMTAB = 2
EM_X86_64 = 62
ET_EXEC = 2

# --- PE constants ----------------------------------------------------------

SECTION_ALIGN = 0x1000
FILE_ALIGN = 0x200

IMAGE_SCN_CNT_CODE = 0x00000020
IMAGE_SCN_CNT_INITIALIZED_DATA = 0x00000040
IMAGE_SCN_MEM_EXECUTE = 0x20000000
IMAGE_SCN_MEM_READ = 0x40000000
IMAGE_SCN_MEM_WRITE = 0x80000000

IMAGE_FILE_EXECUTABLE_IMAGE = 0x0002
IMAGE_FILE_LARGE_ADDRESS_AWARE = 0x0020
IMAGE_FILE_RELOCS_STRIPPED = 0x0001

IMAGE_DLLCHARACTERISTICS_NX_COMPAT = 0x0100

PE32P_MAGIC = 0x20B
SUBSYSTEM_EFI_APPLICATION = 10
MACHINE_AMD64 = 0x8664
NUM_RVA_AND_SIZES = 16

DOS_HEADER_SIZE = 0x80  # includes the classic 64-byte header and stub space


class ElfError(Exception):
    pass


def align(value, alignment):
    return (value + alignment - 1) & ~(alignment - 1)


class ElfImage:
    def __init__(self, data):
        if len(data) < 64 or data[:4] != b"\x7fELF":
            raise ElfError("not an ELF file")
        if data[4] != 2:
            raise ElfError("not an ELF64 file")
        if data[5] != 1:
            raise ElfError("not a little-endian ELF file")

        (e_type, e_machine) = struct.unpack_from("<HH", data, 16)
        if e_type != ET_EXEC:
            raise ElfError(f"expected ET_EXEC, got e_type={e_type} "
                           "(link with -no-pie)")
        if e_machine != EM_X86_64:
            raise ElfError(f"expected EM_X86_64, got e_machine={e_machine}")

        self.entry = struct.unpack_from("<Q", data, 24)[0]
        e_phoff = struct.unpack_from("<Q", data, 32)[0]
        e_shoff = struct.unpack_from("<Q", data, 40)[0]
        e_phentsize, e_phnum = struct.unpack_from("<HH", data, 54)
        e_shentsize = struct.unpack_from("<H", data, 58)[0]
        e_shnum = struct.unpack_from("<H", data, 60)[0]

        self.loads = []
        for i in range(e_phnum):
            off = e_phoff + i * e_phentsize
            (p_type, p_flags, p_offset, p_vaddr, _p_paddr,
             p_filesz, p_memsz, _p_align) = struct.unpack_from(
                "<IIQQQQQQ", data, off)
            if p_type == PT_LOAD and p_memsz > 0:
                self.loads.append({
                    "flags": p_flags,
                    "offset": p_offset,
                    "vaddr": p_vaddr,
                    "filesz": p_filesz,
                    "memsz": p_memsz,
                    "data": data[p_offset:p_offset + p_filesz],
                })
        if not self.loads:
            raise ElfError("no PT_LOAD segments")
        self.loads.sort(key=lambda s: s["vaddr"])

        # Symbol table, for the entry shim address.
        self.symbols = {}
        for i in range(e_shnum):
            off = e_shoff + i * e_shentsize
            (_name, sh_type, _flags, _addr, sh_offset, sh_size,
             sh_link, _info, _align, _entsize) = struct.unpack_from(
                "<IIQQQQIIQQ", data, off)
            if sh_type != SHT_SYMTAB:
                continue
            str_off = struct.unpack_from(
                "<Q", data, e_shoff + sh_link * e_shentsize + 24)[0]
            for j in range(sh_size // 24):
                (st_name, _info, _other, _shndx,
                 st_value, _size) = struct.unpack_from(
                    "<IBBHQQ", data, sh_offset + j * 24)
                end = data.index(b"\0", str_off + st_name)
                name = data[str_off + st_name:end].decode("ascii", "replace")
                self.symbols[name] = st_value


def section_for(load):
    """Return (name, characteristics) for one PT_LOAD segment."""
    if load["flags"] & PF_X:
        return b".text", (IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_READ
                          | IMAGE_SCN_MEM_EXECUTE)
    if load["flags"] & PF_W:
        return b".data", (IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ
                          | IMAGE_SCN_MEM_WRITE)
    return b".rodata", (IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ)


def build_pe(elf, verbose=False):
    # EDK2's PE loader rejects any section whose RVA is below SizeOfHeaders,
    # so the first PT_LOAD must not map at RVA 0.  Place the image one page
    # below the first segment: every section then starts at RVA >= 0x1000 and
    # still lands at its ELF virtual address when the firmware loads the image
    # at ImageBase.
    first_vaddr = elf.loads[0]["vaddr"] & ~(SECTION_ALIGN - 1)
    image_base = first_vaddr - SECTION_ALIGN

    if "efi64_entry" not in elf.symbols:
        raise ElfError("symbol 'efi64_entry' not found in the ELF; "
                       "is src/efi64_entry.s linked in?")
    entry_rva = elf.symbols["efi64_entry"] - image_base

    sections = []
    for load in elf.loads:
        va = load["vaddr"] - image_base
        if va % SECTION_ALIGN:
            raise ElfError(
                f"segment at {load['vaddr']:#x} is not "
                f"{SECTION_ALIGN:#x}-aligned")
        if sections and va < sections[-1]["va"] + sections[-1]["vsize"]:
            raise ElfError(f"PT_LOAD segments overlap at {va:#x}")
        name, chars = section_for(load)
        sections.append({
            "name": name,
            "va": va,
            "vsize": max(load["memsz"], load["filesz"]),
            "chars": chars,
            "raw": load["data"],
        })

    num_sections = len(sections)
    headers_size = align(
        DOS_HEADER_SIZE + 4 + 20 + 0xF0 + 40 * num_sections, FILE_ALIGN)

    # Lay out the raw data.
    file_offset = headers_size
    for sec in sections:
        sec["raw_size"] = align(len(sec["raw"]), FILE_ALIGN)
        sec["raw_offset"] = file_offset
        file_offset += sec["raw_size"]

    image_size = align(
        max(s["va"] + s["vsize"] for s in sections), SECTION_ALIGN)

    size_of_code = sum(s["raw_size"] for s in sections
                       if s["chars"] & IMAGE_SCN_MEM_EXECUTE)
    size_of_init = sum(s["raw_size"] for s in sections
                       if not s["chars"] & IMAGE_SCN_MEM_EXECUTE)
    base_of_code = next(s["va"] for s in sections
                        if s["chars"] & IMAGE_SCN_MEM_EXECUTE)

    # --- DOS header -------------------------------------------------------
    out = bytearray(headers_size)
    out[0:2] = b"MZ"
    # 0x3C holds the offset of the PE signature.
    struct.pack_into("<I", out, 0x3C, DOS_HEADER_SIZE)

    # --- PE signature + COFF header --------------------------------------
    pe = DOS_HEADER_SIZE
    out[pe:pe + 4] = b"PE\0\0"
    coff = pe + 4
    characteristics = (IMAGE_FILE_EXECUTABLE_IMAGE
                       | IMAGE_FILE_LARGE_ADDRESS_AWARE
                       | IMAGE_FILE_RELOCS_STRIPPED)
    struct.pack_into("<HHIIIHH", out, coff,
                     MACHINE_AMD64,
                     num_sections,
                     0,                     # TimeDateStamp
                     0,                     # PointerToSymbolTable
                     0,                     # NumberOfSymbols
                     0xF0,                  # SizeOfOptionalHeader (PE32+)
                     characteristics)

    # --- Optional header (PE32+) ------------------------------------------
    opt = coff + 20
    struct.pack_into("<HBBIIIII", out, opt,
                     PE32P_MAGIC,
                     0, 0,                  # linker version
                     size_of_code,
                     size_of_init,
                     0,                     # SizeOfUninitializedData
                     entry_rva,
                     base_of_code)
    struct.pack_into("<QII", out, opt + 24,
                     image_base,
                     SECTION_ALIGN,
                     FILE_ALIGN)
    struct.pack_into("<HHHHHH", out, opt + 40,
                     0, 0,                  # OS version
                     0, 0,                  # image version
                     0, 0)                  # subsystem version
    struct.pack_into("<IIII", out, opt + 52,
                     0,                     # Win32VersionValue
                     image_size,
                     headers_size,
                     0)                     # CheckSum
    struct.pack_into("<HH", out, opt + 68,
                     SUBSYSTEM_EFI_APPLICATION,
                     IMAGE_DLLCHARACTERISTICS_NX_COMPAT)
    struct.pack_into("<QQQQ", out, opt + 72,
                     0x100000, 0x1000,      # stack reserve / commit
                     0x100000, 0x1000)      # heap reserve / commit
    struct.pack_into("<II", out, opt + 104,
                     0,                     # LoaderFlags
                     NUM_RVA_AND_SIZES)
    # Data directories (all zero: no .reloc, no imports, no debug info).

    # --- Section headers ---------------------------------------------------
    sh = opt + 0xF0
    for i, sec in enumerate(sections):
        entry_off = sh + i * 40
        out[entry_off:entry_off + 8] = sec["name"].ljust(8, b"\0")
        struct.pack_into("<IIII", out, entry_off + 8,
                         sec["vsize"],
                         sec["va"],
                         sec["raw_size"],
                         sec["raw_offset"])
        struct.pack_into("<IIHHI", out, entry_off + 24,
                         0, 0, 0, 0, sec["chars"])

    # --- Section contents --------------------------------------------------
    # The file must be padded out to each section's full SizeOfRawData: EDK2's
    # PE loader validates a section by reading its very last raw byte, so a
    # short final section makes LoadImage fail with EFI_UNSUPPORTED.
    for sec in sections:
        start = sec["raw_offset"]
        padded = sec["raw"] + b"\0" * (sec["raw_size"] - len(sec["raw"]))
        out[start:start + sec["raw_size"]] = padded

    if verbose:
        print(f"ELF entry            0x{elf.entry:016x}")
        print(f"entry shim (RVA)     0x{entry_rva:08x}")
        print(f"image base           0x{image_base:016x}")
        print(f"image size           0x{image_size:08x}")
        print(f"headers size         0x{headers_size:08x}")
        for sec in sections:
            print(f"  {sec['name'].decode():8s} va=0x{sec['va']:08x} "
                  f"vsize=0x{sec['vsize']:08x} raw=0x{sec['raw_size']:08x} "
                  f"chars=0x{sec['chars']:08x}")

    return bytes(out), image_base, entry_rva


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", help="input freestanding ELF64 executable")
    parser.add_argument("pe", help="output PE32+ UEFI image")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    with open(args.elf, "rb") as f:
        data = f.read()

    try:
        pe, base, entry = build_pe(ElfImage(data), args.verbose)
    except ElfError as exc:
        sys.exit(f"elf2pe: {exc}")

    with open(args.pe, "wb") as f:
        f.write(pe)

    print(f"elf2pe: wrote {args.pe} "
          f"({len(pe)} bytes, base 0x{base:x}, entry rva 0x{entry:x})")


if __name__ == "__main__":
    main()
