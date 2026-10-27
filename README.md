# liminade - Limine-Compatible UEFI Bootloader in Ada

liminade is a UEFI bootloader written in Ada that supports the [Limine Boot Protocol](https://github.com/limine-bootloader/limine-protocol). It loads kernels that embed Limine request structures and processes them before transferring control to the kernel.

## Status

Milestones 1 and 2 are complete.  liminade builds as a real PE32+ UEFI
application from Ada sources, and under QEMU/OVMF it

1. opens the ESP, loads the kernel ELF (Limine request scanning, PT_LOAD
   placement at the kernel's link addresses) plus its modules,
2. builds every rev-6 response (base revision, bootloader info, HHDM, memory
   map, entry point, cmdline, paging mode, MP, RSDP, date at boot, modules),
3. exits boot services, installs its own **4-level** page tables (identity map
   of the low 4 GiB, HHDM at `0xffff800000000000`, kernel segments with
   per-segment permissions), and jumps to the kernel with the machine state the
   protocol requires.

Verified end-to-end against Terra: the Theia prekernel boots `lunar.elf`,
mounts the initramfs and reaches the userspace shell with `./run-qemu.sh`
printing `RESULT: PASS`.

Milestones 3 (real AP startup / MP handoff) and 4 (Terra packaging:
`liminade.lua`, `make_image.py`, `qemu.py --liminade`) are still open; see
`AGENTS.md`.

### Testing against Terra

`run-qemu.sh` assembles a FAT32 ESP with mtools (no root needed) containing
`EFI/BOOT/BOOTX64.EFI`, `/boot/lunar.elf`, `/boot/initramfs.rdk.gz` and
`/boot/kernel.ksym`, then boots QEMU/OVMF headless and greps the COM1 log.

```bash
./run-qemu.sh                              # expects "mounted initramfs"
EXPECT="bash-" ./run-qemu.sh               # wait for the userspace shell
TIMEOUT_SECS=60 TERRA_DEST=/path/to/dest ./run-qemu.sh
OVMF_DIR=/path/to/edk2-ovmf ./run-qemu.sh  # different firmware
MEMORY=1G ./run-qemu.sh                    # more RAM
```

The serial log is kept in `build/serial.log`.

## Building

```bash
# Build the UEFI image (Ada -> freestanding ELF64 -> PE32+)
./build.sh                     # -> build/liminade.efi

# Or through Nix (produces an identical image)
nix build .#liminade          # -> result/bin/liminade.efi

# Boot the locally built image under QEMU + OVMF and check the COM1 log
./run-qemu.sh                  # prints "RESULT: PASS" when the probe succeeds
```

The build pipeline exists because nixpkgs has no Ada compiler that targets
PE/COFF: GNAT emits a freestanding ELF executable which `tools/elf2pe.py`
repackages as a PE32+ EFI application (Machine 0x8664, subsystem 10).

UEFI firmware calls functions with the MS x64 ABI, while GNAT emits System V;
all firmware calls go through the `ms_call6` trampoline in `src/ms_abi.s`.

## Booting a Limine Boot Protocol Kernel

### 1. Prepare the EFI System Partition

Create a FAT32 partition and mount it:

```bash
# Create a disk image (for testing)
qemu-img create -f qcow2 bootdisk.img 512M

# Partition it
fdisk bootdisk.img <<EOF
n
p
1


t
c
a
w
EOF

# Create FAT32 filesystem
losetup -f bootdisk.img
losetup -l | grep bootdisk.img
# Note the loop device, e.g. /dev/loop0

mkfs.vfat /dev/loop0p1
mount /dev/loop0p1 /mnt
```

### 2. Copy Bootloader and Kernel

```bash
# Copy the liminade bootloader
cp result/bin/liminade.efi /mnt/EFI/BOOT/BOOTX64.EFI

# Copy your LBP kernel (example: kernel.elf with Limine requests)
cp /path/to/your/lbp-kernel.elf /mnt/kernel.elf
```

### 3. Kernel location

The kernel path is currently **fixed at `/boot/lunar.elf`** on the ESP
(limine.conf / `KERNEL_PATH` parsing is not implemented yet).  Limine module
requests with bare filenames are resolved relative to `/boot/` as well.

### 4. Boot with QEMU

The simplest route is the ready-made script, which builds the ESP with mtools
and runs OVMF:

```bash
./run-qemu.sh
```

Or manually:

```bash
qemu-system-x86_64 \
    -machine q35,accel=tcg,smm=off \
    -cpu max,la57=on,x2apic=on \
    -m 512M -smp 2 -serial stdio \
    -drive if=pflash,format=raw,unit=0,readonly=on,file=ovmf-code-x86_64.fd \
    -drive if=pflash,format=raw,unit=1,file=ovmf-vars.fd \
    -drive file=bootdisk.img,format=qcow2
```

## Creating a Limine Boot Protocol Kernel

Your kernel must embed Limine request structures in its image. Here's a C example:

### Example Kernel with Limine Requests (C)

```c
// kernel.c - Example LBP kernel

#define LIMINE_COMMON_MAGIC_1 0xC7B1DD30DF4C8B88ULL
#define LIMINE_COMMON_MAGIC_2 0x0A82E883A194F07BULL

#define LIMINE_BASE_REVISION_MAGIC_1 0xF9567B2D5C95A6C8ULL
#define LIMINE_BASE_REVISION_MAGIC_2 0x6A7B384944536BDCULL
#define LIMINE_BASE_REVISION 6

// Request: Memory Map
#define LIMINE_MEMMAP_REQUEST_ID_1 0x67CF3D9D378A806FULL
#define LIMINE_MEMMAP_REQUEST_ID_2 0xE304ACDFC50C3C62ULL

struct limine_memmap_request {
    unsigned long long id1, id2;
    unsigned long long revision;
    unsigned long long response;
};

struct limine_memmap_response {
    unsigned long long revision;
    unsigned long long entries;
    void *entries_array;
};

struct limine_memmap_entry {
    unsigned long long base;
    unsigned long long length;
    unsigned long long type;
    unsigned long long flags;
};

// Embed request in kernel image
struct limine_memmap_request limine_memmap_request = {
    .id1 = LIMINE_COMMON_MAGIC_1,
    .id2 = LIMINE_COMMON_MAGIC_2,
    .revision = 0,
    .response = 0
};

// Base revision tag
struct {
    unsigned long long id1;
    unsigned long long id2;
    unsigned long long revision;
} limine_base_revision = {
    .id1 = LIMINE_BASE_REVISION_MAGIC_1,
    .id2 = LIMINE_BASE_REVISION_MAGIC_2,
    .revision = LIMINE_BASE_REVISION
};

// Entry point
void kernel_entry(void *stack, unsigned long long stack_size) {
    // Process Limine requests (response pointers should be filled by bootloader)
    
    // Example: Get memory map
    if (limine_memmap_request.response != 0) {
        struct limine_memmap_response *resp = 
            (struct limine_memmap_response *)limine_memmap_request.response;
        
        for (unsigned long long i = 0; i < resp->entries; i++) {
            struct limine_memmap_entry *entry = 
                ((struct limine_memmap_entry *)resp->entries_array)[i];
            // Process memory map entry...
        }
    }
    
    // Kernel main loop...
    while (1) {
        // ...
    }
}
```

Compile the kernel:
```bash
x86_64-elf-gcc -c kernel.c -o kernel.o
x86_64-elf-ld -T linker.ld -o kernel.elf kernel.o
```

### Example Kernel with Limine Requests (Ada)

```ada
-- kernel.ads
with Interfaces;
use Interfaces;
with System;

package Kernel is
    -- Limine common magic
    LIMINE_COMMON_MAGIC_1 : constant Interfaces.Unsigned_64 := 16#C7B1DD30DF4C8B88#;
    LIMINE_COMMON_MAGIC_2 : constant Interfaces.Unsigned_64 := 16#0A82E883A194F07B#;
    
    -- Memory map request
    LIMINE_MEMMAP_REQUEST_ID_1 : constant Interfaces.Unsigned_64 := 16#67CF3D9D378A806F#;
    LIMINE_MEMMAP_REQUEST_ID_2 : constant Interfaces.Unsigned_64 := 16#E304ACDFC50C3C62#;
    
    type Limine_Request is record
        id1      : Interfaces.Unsigned_64;
        id2      : Interfaces.Unsigned_64;
        revision : Interfaces.Integer_64;
        response : System.Address;
    end record;
    
    -- Embed request
    Limine_Memmap_Request : Limine_Request;
    
    procedure Kernel_Entry;
end Kernel;
```

```ada
-- kernel.adb
with Interfaces;
use Interfaces;
with System;

package body Kernel is
    procedure Kernel_Entry is
    begin
        -- Process Limine requests
        if Limine_Memmap_Request.response /= System.Null_Address then
            -- Get memory map from bootloader
        end if;
        
        -- Kernel main...
    end Kernel_Entry;
end Kernel;
```

## Limine Request Types Supported

liminade supports the following Limine request types:

| Request ID | Type | Description |
|------------|------|-------------|
| Bootloader Info | `0xF55038D8E2A1202F` / `0x279426FCF5F59740` | Bootloader name/version |
| Command Line | `0x4B161536E598651E` / `0xB390AD4A2F1F303A` | Kernel command line |
| Firmware Type | `0x8C2F75D90BEF28A8` / `0x7045A4688EAC00C3` | UEFI firmware type (2) |
| Stack Size | `0x224EF0460A8E8926` / `0xE1CB0FC25F46EA3D` | Empty response (default stack) |
| HHDM | `0x48DCF1CB8AD2B852` / `0x63984E959A98244B` | High-half direct map at `0xffff800000000000` |
| Framebuffer | `0x9D5827DCD881DD75` / `0xA3148604F6FAB11B` | GOP mode 0 (absent when headless) |
| Paging Mode | `0x95C1A0EDAB0944CB` / `0xA4E5CB3842F7488A` | 4-level x86_64 (value 0) |
| MP | `0x95A67B819A1B857E` / `0xA0B61B723B6A73E0` | BSP only so far (`.limine_mp_info` array) |
| Memory Map | `0x67CF3D9D378A806F` / `0xE304ACDFC50C3C62` | Array of pointers to 24-byte entries |
| Entry Point | `0x13D86C035A1CD3E1` / `0x2B0CAA89D8F3026A` | Custom kernel entry |
| Modules | `0x3E7E279702BE32AF` / `0xCA1C4F3BD1280CEE` | Rev 1, internal modules, resolved paths |
| RSDP | `0xC5E77B6B397E7B43` / `0x27637845ACCDCF3C` | ACPI 2.0 (else 1.0) RSDP |
| Date at Boot | `0x502746E184C088AA` / `0xFBC5EC83E6327893` | Runtime services `GetTime` |
| DTB | `0xB40DDB48FB54BAC7` / `0x545081493F81FFB7` | No device tree on x86 |
| Executable File | `0xAD97E90E83F1ED67` / `0x31EB5D1C5FF23B69` | Kernel file info |

## Architecture

liminade is written in Ada and follows this architecture:

- **UEFI Entry Point**: `efi_main()` called by UEFI firmware
- **Limine Protocol Layer**: Scans kernel image for request structures, processes requests
- **ELF Loader**: Loads kernel ELF images from disk
- **Memory Management**: Handles kernel memory allocation and mapping
- **SMP Support**: Multi-processor initialization framework

## Development

```bash
# Enter development shell
nix develop

# Build and boot-test
./build.sh
./run-qemu.sh
```

Project state, design notes, Ada/GNAT gotchas and the milestone plan live in
`AGENTS.md`.  In particular: never call a firmware function pointer directly
(use `EFI.MS_Call6`), and keep `tools/elf2pe.py`'s EDK2 loader constraints
intact.

## License

MIT
