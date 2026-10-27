--  Limine boot protocol constants (base revision 6).
--
--  The request/response structures are described with the byte offsets used
--  by <limine.h>; see tools/limine.h for the vendored reference header.

with Interfaces; use Interfaces;

package Limine is
   pragma Preelaborate;

   ------------------------------
   --  Request / response magic
   ------------------------------

   COMMON_MAGIC_1 : constant Unsigned_64 := 16#C7B1DD30DF4C8B88#;
   COMMON_MAGIC_2 : constant Unsigned_64 := 16#0A82E883A194F07B#;

   START_MARKER_1 : constant Unsigned_64 := 16#F6B8F4B39DE7D1AE#;
   START_MARKER_2 : constant Unsigned_64 := 16#FAB91A6940FCB9CF#;
   END_MARKER_1   : constant Unsigned_64 := 16#ADC0E0531BB10D03#;
   END_MARKER_2   : constant Unsigned_64 := 16#9572709F31764C62#;

   BASE_REVISION_MARKER_1 : constant Unsigned_64 := 16#F9562B2D5C95A6C8#;
   BASE_REVISION_MARKER_2 : constant Unsigned_64 := 16#6A7B384944536BDC#;

   BASE_REVISION : constant Unsigned_64 := 6;

   ------------------------------------------
   --  Request IDs (the last two u64 words)
   ------------------------------------------

   type ID_Tail is record
      A : Unsigned_64;
      B : Unsigned_64;
   end record with Convention => C;

   ID_BOOTLOADER_INFO : constant ID_Tail := (16#F55038D8E2A1202F#, 16#279426FCF5F59740#);
   ID_CMDLINE         : constant ID_Tail := (16#4B161536E598651E#, 16#B390AD4A2F1F303A#);
   ID_FIRMWARE_TYPE   : constant ID_Tail := (16#8C2F75D90BEF28A8#, 16#7045A4688EAC00C3#);
   ID_STACK_SIZE      : constant ID_Tail := (16#224EF0460A8E8926#, 16#E1CB0FC25F46EA3D#);
   ID_HHDM            : constant ID_Tail := (16#48DCF1CB8AD2B852#, 16#63984E959A98244B#);
   ID_FRAMEBUFFER     : constant ID_Tail := (16#9D5827DCD881DD75#, 16#A3148604F6FAB11B#);
   ID_PAGING_MODE     : constant ID_Tail := (16#95C1A0EDAB0944CB#, 16#A4E5CB3842F7488A#);
   ID_MP              : constant ID_Tail := (16#95A67B819A1B857E#, 16#A0B61B723B6A73E0#);
   ID_MEMMAP          : constant ID_Tail := (16#67CF3D9D378A806F#, 16#E304ACDFC50C3C62#);
   ID_ENTRY_POINT     : constant ID_Tail := (16#13D86C035A1CD3E1#, 16#2B0CAA89D8F3026A#);
   ID_MODULE          : constant ID_Tail := (16#3E7E279702BE32AF#, 16#CA1C4F3BD1280CEE#);
   ID_RSDP            : constant ID_Tail := (16#C5E77B6B397E7B43#, 16#27637845ACCDCF3C#);
   ID_DATE_AT_BOOT    : constant ID_Tail := (16#502746E184C088AA#, 16#FBC5EC83E6327893#);
   ID_DTB             : constant ID_Tail := (16#B40DDB48FB54BAC7#, 16#545081493F81FFB7#);
   ID_EXECUTABLE_FILE : constant ID_Tail := (16#AD97E90E83F1ED67#, 16#31EB5D1C5FF23B69#);

   ---------------------------------------------
   --  Request field offsets (all u64 aligned)
   ---------------------------------------------

   REQ_REVISION_OFFSET      : constant := 32;
   REQ_RESPONSE_OFFSET      : constant := 40;

   ENTRY_POINT_ENTRY_OFFSET : constant := 48;

   MP_FLAGS_OFFSET          : constant := 48;

   PAGING_MODE_MODE_OFFSET  : constant := 48;
   PAGING_MODE_MAX_OFFSET   : constant := 56;
   PAGING_MODE_MIN_OFFSET   : constant := 64;

   MODULE_COUNT_OFFSET      : constant := 48;
   MODULE_ARRAY_OFFSET      : constant := 56;

   BASE_REVISION_OFFSET     : constant := 8;   --  revision/supported word
   BASE_REVISION_FLAGS      : constant := 16;  --  0 => protocol supported

   --------------------------
   --  Paging mode responses
   --------------------------

   PAGING_MODE_X86_64_4LVL : constant := 0;
   PAGING_MODE_X86_64_5LVL : constant := 1;

   -------------------
   --  Firmware types
   -------------------

   FIRMWARE_TYPE_X86BIOS : constant := 0;
   FIRMWARE_TYPE_EFI32   : constant := 1;
   FIRMWARE_TYPE_EFI64   : constant := 2;
   FIRMWARE_TYPE_SBI     : constant := 3;

   ----------------------
   --  Memory map types
   ----------------------

   MEMMAP_USABLE                 : constant := 0;
   MEMMAP_RESERVED               : constant := 1;
   MEMMAP_ACPI_RECLAIMABLE       : constant := 2;
   MEMMAP_ACPI_NVS               : constant := 3;
   MEMMAP_BAD_MEMORY             : constant := 4;
   MEMMAP_BOOTLOADER_RECLAIMABLE : constant := 5;
   MEMMAP_EXECUTABLE_AND_MODULES : constant := 6;
   MEMMAP_FRAMEBUFFER            : constant := 7;
   MEMMAP_RESERVED_MAPPED        : constant := 8;

   --------------------
   --  Response sizes
   --------------------

   SIZE_REVISION_ONLY          : constant := 8;
   SIZE_MEMORY_MAP_ENTRY   : constant := 24;
   SIZE_MEMORY_MAP_RESPONSE : constant := 24;
   SIZE_BOOTLOADER_INFO_RESPONSE : constant := 24;
   SIZE_CMDLINE_RESPONSE   : constant := 16;
   SIZE_HHDM_RESPONSE      : constant := 16;
   SIZE_FRAMEBUFFER_RESPONSE : constant := 24;
   SIZE_FRAMEBUFFER        : constant := 80;
   SIZE_PAGING_MODE_RESPONSE : constant := 16;
   SIZE_MP_RESPONSE        : constant := 32;
   SIZE_MP_INFO            : constant := 32;
   SIZE_MODULE_RESPONSE    : constant := 24;
   SIZE_FILE               : constant := 112;
   SIZE_RSDP_RESPONSE      : constant := 16;
   SIZE_DTB_RESPONSE       : constant := 16;
   SIZE_DATE_AT_BOOT_RESPONSE : constant := 16;
   SIZE_ENTRY_POINT_RESPONSE : constant := 8;
   SIZE_FIRMWARE_TYPE_RESPONSE : constant := 16;

   --------------------------------
   --  Response field offsets
   --------------------------------

   --  memory map response: revision, entry_count, entries
   MMAP_ENTRY_COUNT : constant := 8;
   MMAP_ENTRIES     : constant := 16;

   --  memory map entry: base, length, type
   MMAP_ENTRY_BASE   : constant := 0;
   MMAP_ENTRY_LENGTH : constant := 8;
   MMAP_ENTRY_TYPE   : constant := 16;

   BOOTLOADER_INFO_NAME    : constant := 8;
   BOOTLOADER_INFO_VERSION : constant := 16;

   CMDLINE_STRING : constant := 8;

   HHDM_RESPONSE_OFFSET : constant := 8;

   FB_COUNT        : constant := 8;
   FB_ARRAY        : constant := 16;

   FB_ADDRESS      : constant := 0;
   FB_WIDTH        : constant := 8;
   FB_HEIGHT       : constant := 16;
   FB_PITCH        : constant := 24;
   FB_BPP          : constant := 32;
   FB_MEMORY_MODEL : constant := 34;
   FB_RED_SIZE     : constant := 35;
   FB_RED_SHIFT    : constant := 36;
   FB_GREEN_SIZE   : constant := 37;
   FB_GREEN_SHIFT  : constant := 38;
   FB_BLUE_SIZE    : constant := 39;
   FB_BLUE_SHIFT   : constant := 40;
   FB_EDID_SIZE    : constant := 48;
   FB_EDID         : constant := 56;

   PAGING_MODE_MODE : constant := 8;

   MP_FLAGS_RESULT  : constant := 8;   --  u32
   MP_BSP_LAPIC_ID  : constant := 12;  --  u32
   MP_CPU_COUNT     : constant := 16;
   MP_CPUS          : constant := 24;

   MP_INFO_PROCESSOR_ID   : constant := 0;
   MP_INFO_LAPIC_ID       : constant := 4;
   MP_INFO_RESERVED       : constant := 8;
   MP_INFO_GOTO_ADDRESS   : constant := 16;
   MP_INFO_EXTRA_ARGUMENT : constant := 24;

   MODULE_RESPONSE_COUNT : constant := 8;
   MODULE_RESPONSE_ARRAY : constant := 16;

   FILE_REVISION     : constant := 0;
   FILE_ADDRESS      : constant := 8;
   FILE_SIZE         : constant := 16;
   FILE_PATH         : constant := 24;
   FILE_STRING       : constant := 32;
   FILE_MEDIA_TYPE   : constant := 40;
   FILE_UNUSED       : constant := 44;

   RSDP_ADDRESS : constant := 8;
   DTB_ADDRESS  : constant := 8;

   DATE_AT_BOOT_TIMESTAMP : constant := 8;

   FIRMWARE_TYPE_VALUE : constant := 8;

   ----------------------
   --  Misc values
   ----------------------

   FRAMEBUFFER_RGB : constant := 1;
   MEDIA_TYPE_GENERIC : constant := 0;

   MP_RESPONSE_X86_64_X2APIC : constant := 1;

   --  The HHDM base liminade uses (canonical, top 2 GiB of the 4-level
   --  address space; the kernel image lives just below it).
   HHDM_OFFSET : constant Unsigned_64 := 16#FFFF_8000_0000_0000#;

end Limine;
