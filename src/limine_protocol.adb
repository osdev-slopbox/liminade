with Ada.Unchecked_Conversion;
with System;
with Interfaces; use Interfaces;

with Memory;
with EFI;
with Limine;

package body Limine_Protocol is

   use Memory;
   use type System.Address;
   use type Limine.ID_Tail;

   function As_Descriptor is new Ada.Unchecked_Conversion
     (System.Address, EFI.EFI_MEMORY_DESCRIPTOR_ACCESS);

   -------------
   --  Scan
   -------------

   function Classify (Addr : Unsigned_64) return Request_Kind is
      A : constant Unsigned_64 := Load64 (To_Address (Addr + 16));
      B : constant Unsigned_64 := Load64 (To_Address (Addr + 24));
   begin
      if A = Limine.ID_BOOTLOADER_INFO.A and then B = Limine.ID_BOOTLOADER_INFO.B then
         return Bootloader_Info;
      elsif A = Limine.ID_CMDLINE.A and then B = Limine.ID_CMDLINE.B then
         return Cmdline;
      elsif A = Limine.ID_FIRMWARE_TYPE.A and then B = Limine.ID_FIRMWARE_TYPE.B then
         return Firmware_Type;
      elsif A = Limine.ID_STACK_SIZE.A and then B = Limine.ID_STACK_SIZE.B then
         return Stack_Size;
      elsif A = Limine.ID_HHDM.A and then B = Limine.ID_HHDM.B then
         return Hhdm;
      elsif A = Limine.ID_FRAMEBUFFER.A and then B = Limine.ID_FRAMEBUFFER.B then
         return Framebuffer;
      elsif A = Limine.ID_PAGING_MODE.A and then B = Limine.ID_PAGING_MODE.B then
         return Paging_Mode;
      elsif A = Limine.ID_MP.A and then B = Limine.ID_MP.B then
         return Mp;
      elsif A = Limine.ID_MEMMAP.A and then B = Limine.ID_MEMMAP.B then
         return Memmap;
      elsif A = Limine.ID_ENTRY_POINT.A and then B = Limine.ID_ENTRY_POINT.B then
         return Entry_Point;
      elsif A = Limine.ID_MODULE.A and then B = Limine.ID_MODULE.B then
         return Modules;
      elsif A = Limine.ID_RSDP.A and then B = Limine.ID_RSDP.B then
         return Rsdp;
      elsif A = Limine.ID_DATE_AT_BOOT.A and then B = Limine.ID_DATE_AT_BOOT.B then
         return Date_At_Boot;
      elsif A = Limine.ID_DTB.A and then B = Limine.ID_DTB.B then
         return Dtb;
      elsif A = Limine.ID_EXECUTABLE_FILE.A and then B = Limine.ID_EXECUTABLE_FILE.B then
         return Executable_File;
      else
         return Unknown;
      end if;
   end Classify;

   function Request_Size (Kind : Request_Kind) return Unsigned_64 is
   begin
      case Kind is
         when Entry_Point | Mp =>
            return 56;
         when Paging_Mode =>
            return 72;
         when Modules =>
            return 64;
         when Unknown =>
            return 8;
         when others =>
            return 48;
      end case;
   end Request_Size;

   procedure Scan_Region
     (Base_Physical : Unsigned_64;
      Size          : Unsigned_64;
      Result        : in out Scan_Result)
   is
      Addr : Unsigned_64 := Base_Physical;
      Last : constant Unsigned_64 := Base_Physical + Size;

      function Word (Off : Unsigned_64) return Unsigned_64 is
        (Load64 (To_Address (Addr + Off)));
   begin
      while Addr + 32 <= Last loop
         if Word (0) = Limine.START_MARKER_1 and then Word (8) = Limine.START_MARKER_2 then
            --  The start marker is followed by the base revision block.
            Addr := Addr + 32;
         elsif Word (0) = Limine.END_MARKER_1 and then Word (8) = Limine.END_MARKER_2 then
            return;
         elsif Word (0) = Limine.BASE_REVISION_MARKER_1
           and then Word (8) = Limine.BASE_REVISION_MARKER_2
         then
            Result.Base_Revision_Address := Addr;
            Result.Has_Base_Revision := True;
            Addr := Addr + 24;
         elsif Word (0) = Limine.COMMON_MAGIC_1 and then Word (8) = Limine.COMMON_MAGIC_2 then
            declare
               Kind : constant Request_Kind := Classify (Addr);
            begin
               if Result.Count < Max_Requests then
                  Result.Count := Result.Count + 1;
                  Result.Requests (Result.Count) := (Kind => Kind, Address => Addr);
               end if;
               Addr := Addr + Request_Size (Kind);
            end;
         else
            Addr := Addr + 8;
         end if;
      end loop;
   end Scan_Region;

   ---------------
   --  Modules
   ---------------

   function Make_Module
     (Path : String; Physical_Address : Unsigned_64; Size : Unsigned_64)
      return Module_Spec
   is
      Result : Module_Spec;
      N      : constant Natural := Natural'Min (Path'Length, Max_Path);
   begin
      for I in 1 .. N loop
         Result.Path (I) := Path (Path'First + I - 1);
      end loop;
      Result.Path_Len := N;
      Result.Physical_Address := Physical_Address;
      Result.Size := Size;
      return Result;
   end Make_Module;

   ---------------
   --  Arena
   ---------------

   type Arena is record
      Base : Unsigned_64 := 0;
      Size : Unsigned_64 := 0;
      Used : Unsigned_64 := 0;
      Ok   : Boolean := True;
   end record;

   function Alloc (A : in out Arena; Size : Unsigned_64) return Unsigned_64 is
      Aligned : constant Unsigned_64 := (A.Used + 15) and not 15;
   begin
      if Aligned + Size > A.Size then
         A.Ok := False;
         return 0;
      end if;
      A.Used := Aligned + Size;
      return A.Base + Aligned;
   end Alloc;

   function Alloc_String (A : in out Arena; S : String) return Unsigned_64 is
      P : constant Unsigned_64 := Alloc (A, Unsigned_64 (S'Length) + 1);
   begin
      if P /= 0 then
         declare
            Ignored : constant Unsigned_64 := Store_String (To_Address (P), S);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      end if;
      return P;
   end Alloc_String;

   procedure W64 (Addr : Unsigned_64; Value : Unsigned_64) is
   begin
      Store64 (To_Address (Addr), Value);
   end W64;

   procedure W32 (Addr : Unsigned_64; Value : Unsigned_32) is
   begin
      Store32 (To_Address (Addr), Value);
   end W32;

   procedure Set_Response (Req_Address : Unsigned_64; Response_Virtual : Unsigned_64) is
   begin
      Store64 (To_Address (Req_Address + Limine.REQ_RESPONSE_OFFSET), Response_Virtual);
   end Set_Response;

   ------------------------
   --  Memory map helpers
   ------------------------

   function Convert_Type (Efi_Type : Unsigned_64) return Unsigned_64 is
   begin
      case Efi_Type is
         when 1 | 2 =>                       --  LoaderCode / LoaderData
            return Limine.MEMMAP_BOOTLOADER_RECLAIMABLE;
         when 3 | 4 | 7 =>                   --  BootServices*, Conventional
            return Limine.MEMMAP_USABLE;
         when 9 =>
            return Limine.MEMMAP_ACPI_RECLAIMABLE;
         when 10 =>
            return Limine.MEMMAP_ACPI_NVS;
         when 8 =>
            return Limine.MEMMAP_BAD_MEMORY;
         when others =>
            return Limine.MEMMAP_RESERVED;
      end case;
   end Convert_Type;

   ------------------------
   --  Populate
   ------------------------

   procedure Populate
     (Requests       : Scan_Result;
      HHDM_Offset           : Unsigned_64;
      Arena_Physical : Unsigned_64;
      Arena_Size     : Unsigned_64;
      Efi_Map        : System.Address;
      Efi_Map_Count  : Natural;
      Efi_Desc_Size  : Unsigned_64;
      Fb_Info        : EFI.GOP.Framebuffer_Info;
      Module_List    : Module_Array;
      Mp_Info_Base   : Unsigned_64 := 0;
      Mp_Flags       : Unsigned_32 := 0;
      Cmdline_Text   : String;
      Rsdp_Physical  : Unsigned_64;
      Has_Rsdp       : Boolean;
      Boot_Timestamp : Unsigned_64;
      Cpu_List       : Cpu_Array;
      Bsp_Lapic_Id   : Unsigned_32;
      Entry_Address  : out Unsigned_64;
      Has_Entry_Point : out Boolean;
      Selected_Paging_Mode : out Unsigned_64;
      Ok             : out Boolean)
   is
      A : Arena := (Base => Arena_Physical, Size => Arena_Size, Used => 0, Ok => True);

      Name_Phys    : constant Unsigned_64 := Alloc_String (A, "liminade");
      Version_Phys : constant Unsigned_64 := Alloc_String (A, "0.2");
      Cmdline_Phys : constant Unsigned_64 := Alloc_String (A, Cmdline_Text);

      Memmap_Entries  : Unsigned_64 := 0;
      Memmap_Pointers : Unsigned_64 := 0;
      Memmap_Count    : Unsigned_64 := 0;
      Memmap_Built    : Boolean := False;

      Fb_Phys : Unsigned_64 := 0;
      Modules_Files  : Unsigned_64 := 0;
      Modules_Ptrs   : Unsigned_64 := 0;
      Mp_Infos       : Unsigned_64 := 0;
      Mp_Ptrs        : Unsigned_64 := 0;
      Timestamp_Resp : Unsigned_64 := 0;
   begin
      Has_Entry_Point := False;
      Entry_Address := 0;
      Selected_Paging_Mode := Limine.PAGING_MODE_X86_64_4LVL;
      Ok := False;

      if Requests.Has_Base_Revision then
         W64 (Requests.Base_Revision_Address + Limine.BASE_REVISION_OFFSET,
              Limine.BASE_REVISION);
         W64 (Requests.Base_Revision_Address + Limine.BASE_REVISION_FLAGS, 0);
      end if;

      --  Framebuffer object is shared by the request handler below.
      if Fb_Info.Present then
         Fb_Phys := Alloc (A, Limine.SIZE_FRAMEBUFFER);
         Zero (To_Address (Fb_Phys), Limine.SIZE_FRAMEBUFFER);
         W64 (Fb_Phys + Limine.FB_ADDRESS, HHDM_Offset + Fb_Info.Physical_Address);
         W64 (Fb_Phys + Limine.FB_WIDTH, Fb_Info.Width);
         W64 (Fb_Phys + Limine.FB_HEIGHT, Fb_Info.Height);
         W64 (Fb_Phys + Limine.FB_PITCH, Fb_Info.Pitch);
         Store16 (To_Address (Fb_Phys + Limine.FB_BPP), Fb_Info.Bpp);
         Store8 (To_Address (Fb_Phys + Limine.FB_MEMORY_MODEL), Limine.FRAMEBUFFER_RGB);
         Store8 (To_Address (Fb_Phys + Limine.FB_RED_SIZE), Fb_Info.Red_Size);
         Store8 (To_Address (Fb_Phys + Limine.FB_RED_SHIFT), Fb_Info.Red_Shift);
         Store8 (To_Address (Fb_Phys + Limine.FB_GREEN_SIZE), Fb_Info.Green_Size);
         Store8 (To_Address (Fb_Phys + Limine.FB_GREEN_SHIFT), Fb_Info.Green_Shift);
         Store8 (To_Address (Fb_Phys + Limine.FB_BLUE_SIZE), Fb_Info.Blue_Size);
         Store8 (To_Address (Fb_Phys + Limine.FB_BLUE_SHIFT), Fb_Info.Blue_Shift);
      end if;

      --  Modules: one limine_file per module plus a pointer array.
      if Module_List'Length > 0 then
         Modules_Files := Alloc (A, unsigned_64 (Module_List'Length) * Limine.SIZE_FILE);
         Modules_Ptrs  := Alloc (A, Unsigned_64 (Module_List'Length) * 8);
         for I in Module_List'Range loop
            declare
               Idx      : constant Unsigned_64 := Unsigned_64 (I - Module_List'First);
               File_P   : constant Unsigned_64 := Modules_Files + Idx * Limine.SIZE_FILE;
               Path_P   : constant Unsigned_64 :=
                 Alloc_String (A, Module_List (I).Path (1 .. Module_List (I).Path_Len));
               Empty_P  : constant Unsigned_64 := Alloc_String (A, "");
            begin
               Zero (To_Address (File_P), Limine.SIZE_FILE);
               W64 (File_P + Limine.FILE_REVISION, 0);
               W64 (File_P + Limine.FILE_ADDRESS, HHDM_Offset + Module_List (I).Physical_Address);
               W64 (File_P + Limine.FILE_SIZE, Module_List (I).Size);
               W64 (File_P + Limine.FILE_PATH, HHDM_Offset + Path_P);
               W64 (File_P + Limine.FILE_STRING, HHDM_Offset + Empty_P);
               W32 (File_P + Limine.FILE_MEDIA_TYPE, Limine.MEDIA_TYPE_GENERIC);
               W64 (Modules_Ptrs + Idx * 8, HHDM_Offset + File_P);
            end;
         end loop;
      end if;

      --  MP info array: allocated and filled in by the MP package (it must be
      --  identity mapped so parked APs can poll goto_address).
      if Cpu_List'Length > 0 then
         Mp_Ptrs := Alloc (A, Unsigned_64 (Cpu_List'Length) * 8);
         for I in Cpu_List'Range loop
            declare
               Idx : constant Unsigned_64 := Unsigned_64 (I - Cpu_List'First);
               Info_P : constant Unsigned_64 :=
                 Mp_Info_Base + Idx * Limine.SIZE_MP_INFO;
            begin
               W64 (Mp_Ptrs + Idx * 8, HHDM_Offset + Info_P);
            end;
         end loop;
      end if;

      --  Date-at-boot response is shared.
      Timestamp_Resp := Alloc (A, Limine.SIZE_DATE_AT_BOOT_RESPONSE);
      W64 (Timestamp_Resp + 0, 0);
      W64 (Timestamp_Resp + Limine.DATE_AT_BOOT_TIMESTAMP, Boot_Timestamp);

      for I in 1 .. Requests.Count loop
         declare
            R : constant Request_Info := Requests.Requests (I);
            Resp : Unsigned_64 := 0;
         begin
            case R.Kind is
               when Bootloader_Info =>
                  Resp := Alloc (A, Limine.SIZE_BOOTLOADER_INFO_RESPONSE);
                  W64 (Resp + 0, 0);
                  W64 (Resp + Limine.BOOTLOADER_INFO_NAME, HHDM_Offset + Name_Phys);
                  W64 (Resp + Limine.BOOTLOADER_INFO_VERSION, HHDM_Offset + Version_Phys);
                  Set_Response (R.Address, HHDM_Offset + Resp);

               when Cmdline =>
                  Resp := Alloc (A, Limine.SIZE_CMDLINE_RESPONSE);
                  W64 (Resp + 0, 0);
                  W64 (Resp + Limine.CMDLINE_STRING, HHDM_Offset + Cmdline_Phys);
                  Set_Response (R.Address, HHDM_Offset + Resp);

               when Firmware_Type =>
                  Resp := Alloc (A, Limine.SIZE_FIRMWARE_TYPE_RESPONSE);
                  W64 (Resp + 0, 0);
                  W64 (Resp + Limine.FIRMWARE_TYPE_VALUE, Limine.FIRMWARE_TYPE_EFI64);
                  Set_Response (R.Address, HHDM_Offset + Resp);

               when Stack_Size =>
                  Resp := Alloc (A, Limine.SIZE_REVISION_ONLY);
                  W64 (Resp, 0);
                  Set_Response (R.Address, HHDM_Offset + Resp);

               when Hhdm =>
                  Resp := Alloc (A, Limine.SIZE_HHDM_RESPONSE);
                  W64 (Resp + 0, 0);
                  W64 (Resp + Limine.HHDM_RESPONSE_OFFSET, HHDM_Offset);
                  Set_Response (R.Address, HHDM_Offset + Resp);

               when Framebuffer =>
                  Resp := Alloc (A, Limine.SIZE_FRAMEBUFFER_RESPONSE);
                  if Fb_Info.Present then
                     declare
                        Array_P : constant Unsigned_64 := Alloc (A, 8);
                     begin
                        W64 (Array_P, HHDM_Offset + Fb_Phys);
                        W64 (Resp + 0, 0);
                        W64 (Resp + Limine.FB_COUNT, 1);
                        W64 (Resp + Limine.FB_ARRAY, HHDM_Offset + Array_P);
                     end;
                  else
                     W64 (Resp + 0, 0);
                     W64 (Resp + Limine.FB_COUNT, 0);
                     W64 (Resp + Limine.FB_ARRAY, 0);
                  end if;
                  Set_Response (R.Address, HHDM_Offset + Resp);

               when Paging_Mode =>
                  declare
                     Max_Mode : constant Unsigned_64 :=
                       Load64 (To_Address (R.Address + Limine.PAGING_MODE_MAX_OFFSET));
                     Min_Mode : constant Unsigned_64 :=
                       Load64 (To_Address (R.Address + Limine.PAGING_MODE_MIN_OFFSET));
                  begin
                     --  liminade implements 4-level paging only.
                     if Min_Mode > Limine.PAGING_MODE_X86_64_4LVL then
                        Ok := False;
                        return;
                     end if;
                     Selected_Paging_Mode := Limine.PAGING_MODE_X86_64_4LVL;
                     if Max_Mode < Selected_Paging_Mode then
                        Ok := False;
                        return;
                     end if;
                     Resp := Alloc (A, Limine.SIZE_PAGING_MODE_RESPONSE);
                     W64 (Resp + 0, 0);
                     W64 (Resp + Limine.PAGING_MODE_MODE, Selected_Paging_Mode);
                     Set_Response (R.Address, HHDM_Offset + Resp);
                  end;

               when Mp =>
                  Resp := Alloc (A, Limine.SIZE_MP_RESPONSE);
                  W64 (Resp + 0, 0);
                  W32 (Resp + Limine.MP_FLAGS_RESULT, Mp_Flags);
                  W32 (Resp + Limine.MP_BSP_LAPIC_ID, Bsp_Lapic_Id);
                  W64 (Resp + Limine.MP_CPU_COUNT, Unsigned_64 (Cpu_List'Length));
                  W64 (Resp + Limine.MP_CPUS, HHDM_Offset + Mp_Ptrs);
                  Set_Response (R.Address, HHDM_Offset + Resp);

               when Memmap =>
                  if not Memmap_Built then
                     declare
                        Total : constant Natural :=
                          Efi_Map_Count + (if Fb_Info.Present then 1 else 0);
                     begin
                        Memmap_Entries := Alloc (A, Unsigned_64 (Total) * Limine.SIZE_MEMORY_MAP_ENTRY);
                        Memmap_Pointers := Alloc (A, Unsigned_64 (Total) * 8);
                        for J in 0 .. Efi_Map_Count - 1 loop
                           declare
                              Desc : constant EFI.EFI_MEMORY_DESCRIPTOR_ACCESS :=
                                As_Descriptor
                                  (To_Address (To_U64 (Efi_Map)
                                               + Unsigned_64 (J) * Efi_Desc_Size));
                              Base : constant Unsigned_64 := Unsigned_64 (Desc.Physical_Start);
                              Len  : constant Unsigned_64 :=
                                Desc.Number_Of_Pages * 16#1000#;
                              Kind : constant Unsigned_64 :=
                                Convert_Type (Unsigned_64 (Desc.Memory_Type));
                              E    : constant Unsigned_64 :=
                                Memmap_Entries + Unsigned_64 (J) * Limine.SIZE_MEMORY_MAP_ENTRY;
                           begin
                              W64 (E + Limine.MMAP_ENTRY_BASE, Base);
                              W64 (E + Limine.MMAP_ENTRY_LENGTH, Len);
                              W64 (E + Limine.MMAP_ENTRY_TYPE, Kind);
                           end;
                        end loop;
                        Memmap_Count := Unsigned_64 (Efi_Map_Count);
                        if Fb_Info.Present then
                           declare
                              E : constant Unsigned_64 :=
                                Memmap_Entries + Memmap_Count * Limine.SIZE_MEMORY_MAP_ENTRY;
                              Len : constant Unsigned_64 :=
                                (Fb_Info.Size + 16#FFF#) and not 16#FFF#;
                           begin
                              W64 (E + Limine.MMAP_ENTRY_BASE, Fb_Info.Physical_Address);
                              W64 (E + Limine.MMAP_ENTRY_LENGTH, Len);
                              W64 (E + Limine.MMAP_ENTRY_TYPE, Limine.MEMMAP_FRAMEBUFFER);
                              Memmap_Count := Memmap_Count + 1;
                           end;
                        end if;
                        for J in 0 .. Memmap_Count - 1 loop
                           W64 (Memmap_Pointers + J * 8,
                               HHDM_Offset + Memmap_Entries + J * Limine.SIZE_MEMORY_MAP_ENTRY);
                        end loop;
                        Memmap_Built := True;
                     end;
                  end if;
                  Resp := Alloc (A, Limine.SIZE_MEMORY_MAP_RESPONSE);
                  W64 (Resp + 0, 0);
                  W64 (Resp + Limine.MMAP_ENTRY_COUNT, Memmap_Count);
                  W64 (Resp + Limine.MMAP_ENTRIES, HHDM_Offset + Memmap_Pointers);
                  Set_Response (R.Address, HHDM_Offset + Resp);

               when Entry_Point =>
                  Entry_Address := Load64 (To_Address (R.Address + Limine.ENTRY_POINT_ENTRY_OFFSET));
                  Has_Entry_Point := True;
                  Resp := Alloc (A, Limine.SIZE_ENTRY_POINT_RESPONSE);
                  W64 (Resp, 0);
                  Set_Response (R.Address, HHDM_Offset + Resp);

               when Modules =>
                  Resp := Alloc (A, Limine.SIZE_MODULE_RESPONSE);
                  W64 (Resp + 0, 0);
                  W64 (Resp + Limine.MODULE_RESPONSE_COUNT, Unsigned_64 (Module_List'Length));
                  W64 (Resp + Limine.MODULE_RESPONSE_ARRAY, HHDM_Offset + Modules_Ptrs);
                  Set_Response (R.Address, HHDM_Offset + Resp);

               when Rsdp =>
                  Resp := Alloc (A, Limine.SIZE_RSDP_RESPONSE);
                  W64 (Resp + 0, 0);
                  if Has_Rsdp then
                     W64 (Resp + Limine.RSDP_ADDRESS, HHDM_Offset + Rsdp_Physical);
                  else
                     W64 (Resp + Limine.RSDP_ADDRESS, 0);
                  end if;
                  Set_Response (R.Address, HHDM_Offset + Resp);

               when Date_At_Boot =>
                  Set_Response (R.Address, HHDM_Offset + Timestamp_Resp);

               when Dtb =>
                  Resp := Alloc (A, Limine.SIZE_DTB_RESPONSE);
                  W64 (Resp + 0, 0);
                  W64 (Resp + Limine.DTB_ADDRESS, 0);
                  Set_Response (R.Address, HHDM_Offset + Resp);

               when Unknown | Executable_File =>
                  null;
            end case;
         end;
      end loop;

      Ok := A.Ok;
   end Populate;

end Limine_Protocol;
