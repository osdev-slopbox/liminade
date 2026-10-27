with Ada.Unchecked_Conversion;
with Interfaces; use Interfaces;
with System;

with EFI;
with EFI.Console;
with EFI.Files;
with EFI.GOP;
with EFI.Services;
with Memory;
with Limine;
with Limine_Protocol;
with Kernel_Loader;
with MP;
with Paging;
with COM1;

package body Liminade is

   use EFI;
   use Memory;
   use type System.Address;
   use type Limine_Protocol.Request_Kind;

   HHDM : constant Unsigned_64 := Limine.HHDM_OFFSET;

   Page_Size        : constant Unsigned_64 := 4096;
   Arena_Bytes      : constant Unsigned_64 := 256 * 1024;
   Stack_Bytes      : constant Unsigned_64 := 64 * 1024;
   Page_Table_Pages : constant Unsigned_64 := 1024;
   Max_Modules      : constant := 8;
   Max_Path         : constant := 160;

   ---------------------------------------------------------------
   --  Firmware shims (src/jump.s)
   ---------------------------------------------------------------

   procedure Switch_Page_Tables (Pml4 : Unsigned_64);
   pragma Import (C, Switch_Page_Tables, "switch_page_tables");

   procedure Jump_To_Kernel (Entry_Address : Unsigned_64; Stack_Top : Unsigned_64);
   pragma Import (C, Jump_To_Kernel, "jump_to_kernel");

   function Cpu_Lapic_Id return Unsigned_32;
   pragma Import (C, Cpu_Lapic_Id, "read_bsp_lapic_id");

   ---------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------

   type Config_Entry_Access is access all EFI_CONFIGURATION_TABLE;

   function As_Config_Entry is new Ada.Unchecked_Conversion
     (System.Address, Config_Entry_Access);
   function As_Descriptor is new Ada.Unchecked_Conversion
     (System.Address, EFI_MEMORY_DESCRIPTOR_ACCESS);

   procedure Log (S : String) renames COM1.Put_Line;

   procedure Fatal (Msg : String) is
   begin
      COM1.Put ("LIMINADE: FATAL: ");
      COM1.Put_Line (Msg);
      loop
         null;
      end loop;
   end Fatal;

   procedure Log_Value (Label : String; Value : Unsigned_64) is
   begin
      COM1.Put (Label);
      COM1.Put_Hex (Value);
      COM1.Put_Line ("");
   end Log_Value;

   procedure Log_Size (Label : String; Value : Unsigned_64) is
   begin
      COM1.Put (Label);
      COM1.Put_Dec (Value);
      COM1.Put_Line (" bytes");
   end Log_Size;

   function Find_Rsdp (Physical : out Unsigned_64) return Boolean is
      ST      : constant EFI_SYSTEM_TABLE_ACCESS := EFI.Services.System_Table;
      N       : Natural;
      Base    : Unsigned_64;
      Conf    : Config_Entry_Access;
   begin
      Physical := 0;
      if ST = null or else ST.Configuration_Table = System.Null_Address then
         return False;
      end if;
      N := Natural (ST.Number_Of_Table_Entries);
      if N > 1024 then
         N := 1024;
      end if;
      Base := To_U64 (ST.Configuration_Table);

      for Pass in 1 .. 2 loop
         for I in 0 .. N - 1 loop
            Conf := As_Config_Entry
              (To_Address (Base + Unsigned_64 (I) * 24));
            if (Pass = 1 and then Conf.Vendor_Guid = ACPI_20_TABLE_GUID)
              or else (Pass = 2 and then Conf.Vendor_Guid = ACPI_10_TABLE_GUID)
            then
               Physical := To_U64 (Conf.Vendor_Table);
               return Physical /= 0;
            end if;
         end loop;
      end loop;
      return False;
   end Find_Rsdp;

   function Days_From_Civil (Y : Integer; M : Integer; D : Integer) return Integer is
      Yy  : Integer := Y;
      Era : Integer;
      Yoe : Integer;
      Doy : Integer;
      Doe : Integer;
   begin
      if M <= 2 then
         Yy := Yy - 1;
      end if;
      Era := (if Yy >= 0 then Yy else Yy - 399) / 400;
      Yoe := Yy - Era * 400;
      Doy := (153 * (M - (if M > 2 then 3 else -9)) + 2) / 5 + D - 1;
      Doe := Yoe * 365 + Yoe / 4 - Yoe / 100 + Doy;
      return Era * 146097 + Doe - 719468;
   end Days_From_Civil;

   function Unix_Timestamp return Unsigned_64 is
      T    : EFI_TIME;
      St   : EFI_STATUS;
      Days : Integer;
   begin
      St := EFI.Services.Get_Time (T);
      if St /= EFI_SUCCESS then
         return 0;
      end if;
      Days := Days_From_Civil (Integer (T.Year), Integer (T.Month), Integer (T.Day));
      return Unsigned_64 (Days) * 86400
        + Unsigned_64 (T.Hour) * 3600
        + Unsigned_64 (T.Minute) * 60
        + Unsigned_64 (T.Second);
   end Unix_Timestamp;

   procedure Read_C_String (Phys : Unsigned_64; Buf : out String; Len : out Natural) is
   begin
      Len := 0;
      for I in Buf'Range loop
         declare
            B : constant Unsigned_8 :=
              Load8 (To_Address (Phys + Unsigned_64 (I - Buf'First)));
         begin
            exit when B = 0;
            Buf (I) := Character'Val (B);
            Len := Len + 1;
         end;
      end loop;
   end Read_C_String;

   function Base_Name_Start (S : String) return Natural is
   begin
      for I in reverse S'Range loop
         if S (I) = '/' or else S (I) = '\' then
            return I + 1;
         end if;
      end loop;
      return S'First;
   end Base_Name_Start;

   procedure Make_Path (Dir : String; Name : String; Buf : out String; Len : out Natural) is
   begin
      Len := 0;
      for I in Dir'Range loop
         exit when Len >= Buf'Length;
         Buf (Buf'First + Len) := Dir (I);
         Len := Len + 1;
      end loop;
      for I in Name'Range loop
         exit when Len >= Buf'Length;
         Buf (Buf'First + Len) := Name (I);
         Len := Len + 1;
      end loop;
   end Make_Path;

   --------------
   -- Run_Boot --
   --------------

   procedure Run_Boot
     (Image_Handle : EFI.EFI_HANDLE;
      System_Table : EFI.EFI_SYSTEM_TABLE_ACCESS)
   is
      Framebuffer  : EFI.GOP.Framebuffer_Info;
      Kernel       : Kernel_Loader.Kernel;
      Scan         : Limine_Protocol.Scan_Result;
      Modules      : Limine_Protocol.Module_Array (1 .. Max_Modules) :=
        (others => Limine_Protocol.Empty_Module);
      Module_Count : Natural := 0;
      Bsp_Lapic    : Unsigned_32 := 0;
      Cpus         : Limine_Protocol.Cpu_Array (1 .. MP.Max_Cpus);

      Arena_Phys   : EFI_PHYSICAL_ADDRESS := 0;
      Stack_Phys   : EFI_PHYSICAL_ADDRESS := 0;

      Map_Buffer   : System.Address := System.Null_Address;
      Map_Capacity : Unsigned_64 := 32768;
      Map_Size     : Unsigned_64 := 0;
      Map_Key      : Unsigned_64 := 0;
      Desc_Size    : Unsigned_64 := 0;
      Desc_Version : Unsigned_32 := 0;
      Map_Count    : Natural := 0;

      Rsdp_Phys    : Unsigned_64 := 0;
      Has_Rsdp     : Boolean := False;

      Root         : Unsigned_64 := 0;
      Entry_Address : Unsigned_64 := 0;
      Has_Entry    : Boolean := False;
      Paging_Mode  : Unsigned_64 := 0;
      Populate_Ok  : Boolean := False;

      St           : EFI_STATUS := EFI_SUCCESS;

      ---------------------------------------------------------
      --  Nested helpers (they need the loaded kernel image)
      ---------------------------------------------------------

      function Va_To_Phys (Va : Unsigned_64) return Unsigned_64 is
      begin
         return Kernel.Physical_Base + (Va - Kernel.Virtual_Base);
      end Va_To_Phys;

      function Descriptor_At (I : Natural) return EFI_MEMORY_DESCRIPTOR_ACCESS is
      begin
         return As_Descriptor
           (To_Address (To_U64 (Map_Buffer) + Unsigned_64 (I) * Desc_Size));
      end Descriptor_At;

      function Load_Module_File
        (Name        : String;
         Phys        : out Unsigned_64;
         Size        : out Unsigned_64;
         Report_Path : out String;
         Report_Len  : out Natural) return Boolean
      is
         Buf : String (1 .. Max_Path);
         Len : Natural;
      begin
         Phys := 0;
         Size := 0;
         Report_Len := 0;

         Make_Path ("\boot\", Name, Buf, Len);
         if Len > 0 and then EFI.Files.Load_File (Buf (1 .. Len), Phys, Size) then
            --  Limine reports the resolved path with forward slashes; the
            --  prekernel/kernel key off the "/boot/" prefix.
            Make_Path ("/boot/", Name, Report_Path, Report_Len);
            return True;
         end if;

         Make_Path ("\", Name, Buf, Len);
         if Len > 0 and then EFI.Files.Load_File (Buf (1 .. Len), Phys, Size) then
            Make_Path ("/", Name, Report_Path, Report_Len);
            return True;
         end if;

         return False;
      end Load_Module_File;

      procedure Load_Internal_Modules (Request_Address : Unsigned_64) is
         Count    : constant Unsigned_64 :=
           Load64 (To_Address (Request_Address + Limine.MODULE_COUNT_OFFSET));
         Array_Va : constant Unsigned_64 :=
           Load64 (To_Address (Request_Address + Limine.MODULE_ARRAY_OFFSET));
         Array_Phys : Unsigned_64;
      begin
         if Count = 0 then
            return;
         end if;
         if Array_Va < Kernel.Virtual_Base then
            Log ("LIMINADE: module array outside kernel image");
            return;
         end if;
         Array_Phys := Va_To_Phys (Array_Va);

         for I in 0 .. Count - 1 loop
            exit when Module_Count >= Max_Modules;
            declare
               Entry_Va   : constant Unsigned_64 :=
                 Load64 (To_Address (Array_Phys + I * 8));
               Entry_Phys : Unsigned_64;
               Path_Va    : Unsigned_64;
               Path_Buf   : String (1 .. 128);
               Path_Len   : Natural;
               Name       : String (1 .. 128);
               Name_Len   : Natural;
               M_Phys     : Unsigned_64;
               M_Size     : Unsigned_64;
               Lim_Path   : String (1 .. 128);
               Lim_Len    : Natural;
            begin
               if Entry_Va < Kernel.Virtual_Base then
                  Log ("LIMINADE: internal module outside kernel image");
               else
                  Entry_Phys := Va_To_Phys (Entry_Va);
                  Path_Va := Load64 (To_Address (Entry_Phys));
                  if Path_Va < Kernel.Virtual_Base then
                     Log ("LIMINADE: module path outside kernel image");
                  else
                     Read_C_String (Va_To_Phys (Path_Va), Path_Buf, Path_Len);
                     if Path_Len > 0 then
                        declare
                           Start : constant Natural := Base_Name_Start (Path_Buf (1 .. Path_Len));
                        begin
                           Name_Len := 0;
                           for J in Start .. Path_Len loop
                              Name_Len := Name_Len + 1;
                              Name (Name_Len) := Path_Buf (J);
                           end loop;
                           COM1.Put ("LIMINADE: module: ");
                           COM1.Put (Name (1 .. Name_Len));
                           COM1.Put_Line ("");
                           if Load_Module_File (Name (1 .. Name_Len), M_Phys, M_Size,
                                                Lim_Path, Lim_Len) then
                              Module_Count := Module_Count + 1;
                              Modules (Module_Count) :=
                                Limine_Protocol.Make_Module
                                  (Lim_Path (1 .. Lim_Len), M_Phys, M_Size);
                              Log_Size ("LIMINADE:   loaded, size ", M_Size);
                           else
                              Log ("LIMINADE:   NOT FOUND on boot volume");
                           end if;
                        end;
                     end if;
                  end if;
               end if;
            end;
         end loop;
      end Load_Internal_Modules;

   begin
      if System_Table = null then
         Fatal ("null system table pointer");
      end if;

      EFI.Services.Initialize (Image_Handle, System_Table);
      Log ("LIMINADE: services initialized");
      St := EFI.Services.Disable_Watchdog;
      Log ("LIMINADE: watchdog disabled");
      if System_Table.Con_Out /= null then
         EFI.Console.Put_Line (System_Table.Con_Out, "liminade 0.2 - Ada Limine bootloader");
      end if;

      if not EFI.Files.Open_Boot_Volume then
         Fatal ("cannot open the boot volume");
      end if;
      Log ("LIMINADE: boot volume opened");

      Framebuffer := EFI.GOP.Get_Framebuffer;
      if Framebuffer.Present then
         Log_Value ("LIMINADE: framebuffer at ", Framebuffer.Physical_Address);
      else
         Log ("LIMINADE: no framebuffer (headless boot)");
      end if;

      Has_Rsdp := Find_Rsdp (Rsdp_Phys);
      if Has_Rsdp then
         Log_Value ("LIMINADE: RSDP at ", Rsdp_Phys);
      else
         Log ("LIMINADE: no RSDP found");
      end if;

      --  Kernel executable.
      declare
         Buf : String (1 .. Max_Path);
         Len : Natural;
         Loaded : Boolean := False;
      begin
         Make_Path ("\boot\", "lunar.elf", Buf, Len);
         if Len > 0 then
            Loaded := Kernel_Loader.Load (Buf (1 .. Len), Kernel);
         end if;
         if not Loaded then
            Make_Path ("\", "lunar.elf", Buf, Len);
            if Len > 0 then
               Loaded := Kernel_Loader.Load (Buf (1 .. Len), Kernel);
            end if;
         end if;
         if not Loaded then
            Fatal ("cannot load lunar.elf");
         end if;
      end;
      Log_Value ("LIMINADE: kernel virtual base  ", Kernel.Virtual_Base);
      Log_Value ("LIMINADE: kernel physical base ", Kernel.Physical_Base);
      Log_Size  ("LIMINADE: kernel image size   ", Kernel.Size);
      Log_Value ("LIMINADE: ELF entry point      ", Kernel.Elf_Entry);

      --  Locate the Limine requests inside the loaded image.
      for I in 1 .. Kernel.Segment_Count loop
         if Kernel.Segments (I).File_Size > 0 then
            Limine_Protocol.Scan_Region
              (Kernel.Segments (I).Physical_Address,
               Kernel.Segments (I).File_Size,
               Scan);
         end if;
      end loop;
      COM1.Put ("LIMINADE: requests found: ");
      COM1.Put_Dec (Unsigned_64 (Scan.Count));
      COM1.Put_Line ("");
      if not Scan.Has_Base_Revision then
         Log ("LIMINADE: WARNING - no base revision request");
      end if;

      --  Modules referenced by the kernel's internal module list.
      for I in 1 .. Scan.Count loop
         if Scan.Requests (I).Kind = Limine_Protocol.Modules then
            Load_Internal_Modules (Scan.Requests (I).Address);
         end if;
      end loop;
      COM1.Put ("LIMINADE: modules loaded: ");
      COM1.Put_Dec (Unsigned_64 (Module_Count));
      COM1.Put_Line ("");

      --  Allocate the response arena, the kernel stack and the page-table
      --  pool before taking the memory-map snapshot used for the map
      --  response and for ExitBootServices.
      St := EFI.Services.Allocate_Pages
        (Memory_Loader_Data, Arena_Bytes / Page_Size, Arena_Phys);
      if St /= EFI_SUCCESS then
         Fatal ("cannot allocate the response arena");
      end if;
      Zero (To_Address (Unsigned_64 (Arena_Phys)), Arena_Bytes);

      St := EFI.Services.Allocate_Pages
        (Memory_Loader_Data, Stack_Bytes / Page_Size, Stack_Phys);
      if St /= EFI_SUCCESS then
         Fatal ("cannot allocate the kernel stack");
      end if;
      Zero (To_Address (Unsigned_64 (Stack_Phys)), Stack_Bytes);

      if not Paging.Initialize (Page_Table_Pages) then
         Fatal ("cannot allocate the page table pool");
      end if;

      --  Snapshot the firmware memory map.
      St := EFI.Services.Allocate_Pool (Memory_Loader_Data, Map_Capacity, Map_Buffer);
      if St /= EFI_SUCCESS then
         Fatal ("cannot allocate the memory map buffer");
      end if;

      loop
         Map_Size := Map_Capacity;
         St := EFI.Services.Get_Memory_Map
           (Map_Buffer, Map_Size, Map_Key, Desc_Size, Desc_Version);
         exit when St = EFI_SUCCESS;
         if St = EFI_BUFFER_TOO_SMALL then
            Map_Capacity := Map_Size + 4096;
            St := EFI.Services.Allocate_Pool
              (Memory_Loader_Data, Map_Capacity, Map_Buffer);
            if St /= EFI_SUCCESS then
               Fatal ("cannot grow the memory map buffer");
            end if;
         else
            Fatal ("GetMemoryMap failed");
         end if;
      end loop;
      if Desc_Size = 0 then
         Fatal ("GetMemoryMap returned a zero descriptor size");
      end if;
      Map_Count := Natural (Map_Size / Desc_Size);
      COM1.Put ("LIMINADE: memory map entries: ");
      COM1.Put_Dec (Unsigned_64 (Map_Count));
      COM1.Put_Line ("");

      --  Build the kernel address space before the APs are released: they run
      --  on these tables and must keep them until the executable switches to
      --  its own address space.
      Root := Paging.New_PML4;
      Paging.Map_Range (Root, 0, 0, Unsigned_64 (4) * 1024 * 1024 * 1024,
                        Writable => True, Executable => True);

      for I in 0 .. Map_Count - 1 loop
         declare
            Desc : constant EFI_MEMORY_DESCRIPTOR_ACCESS := Descriptor_At (I);
            Base : constant Unsigned_64 := Unsigned_64 (Desc.Physical_Start);
            Len  : constant Unsigned_64 := Desc.Number_Of_Pages * Page_Size;
         begin
            if Len > 0 then
               Paging.Map_Range (Root, HHDM + Base, Base, Len,
                                 Writable => True, Executable => False);
            end if;
         end;
      end loop;

      if Framebuffer.Present then
         Paging.Map_Range
           (Root, HHDM + Framebuffer.Physical_Address, Framebuffer.Physical_Address,
            Framebuffer.Size, Writable => True, Executable => False);
      end if;

      Paging.Map_Range (Root, Kernel.Virtual_Base, Kernel.Physical_Base, Kernel.Size,
                        Writable => True, Executable => False);
      for I in 1 .. Kernel.Segment_Count loop
         declare
            Seg : constant Kernel_Loader.Segment := Kernel.Segments (I);
         begin
            Paging.Map_Range (Root, Seg.Virtual_Address, Seg.Physical_Address,
                              Seg.Mem_Size,
                              Writable   => (Seg.Flags and 2) /= 0,
                              Executable => (Seg.Flags and 1) /= 0);
         end;
      end loop;

      if Paging.Pool_Failed then
         Fatal ("page table pool exhausted");
      end if;
      Log ("LIMINADE: page tables built");

      --  Allocate everything the application processors need while the
      --  firmware's boot services are still available.
      MP.Prepare (Rsdp_Physical => Rsdp_Phys, Root => Root);
      if MP.Count = 0 then
         Fatal ("multiprocessor preparation failed");
      end if;

      --  Leave boot services.
      for Attempt in 1 .. 4 loop
         St := EFI.Services.Exit_Boot_Services (Map_Key);
         exit when St = EFI_SUCCESS;
         Log ("LIMINADE: ExitBootServices failed, retrying");
         Map_Size := Map_Capacity;
         St := EFI.Services.Get_Memory_Map
           (Map_Buffer, Map_Size, Map_Key, Desc_Size, Desc_Version);
         if St /= EFI_SUCCESS then
            Fatal ("GetMemoryMap failed during ExitBootServices retry");
         end if;
      end loop;
      if St /= EFI_SUCCESS then
         Fatal ("ExitBootServices failed");
      end if;
      Log ("LIMINADE: boot services exited");

      --  Release the application processors.  They park in long mode on the
      --  page tables above until the executable writes goto_address.  This
      --  has to happen after ExitBootServices: the firmware's MP support
      --  re-parks every AP in its own idle loop while boot services are
      --  being torn down, which would take the APs away from us.
      MP.Release;

      Bsp_Lapic := MP.Cpu (1).Lapic_Id;
      for I in 1 .. MP.Count loop
         Cpus (I) := (Processor_Id => MP.Cpu (I).Processor_Id,
                      Lapic_Id     => MP.Cpu (I).Lapic_Id);
      end loop;
      Log_Value ("LIMINADE: BSP lapic id ", Unsigned_64 (Bsp_Lapic));

      --  Build the Limine responses.  Nothing here needs boot services.
      Limine_Protocol.Populate
        (Requests        => Scan,
         HHDM_Offset     => HHDM,
         Arena_Physical  => Unsigned_64 (Arena_Phys),
         Arena_Size      => Arena_Bytes,
         Efi_Map         => Map_Buffer,
         Efi_Map_Count   => Map_Count,
         Efi_Desc_Size   => Desc_Size,
         Fb_Info         => Framebuffer,
         Module_List     => Modules (1 .. Module_Count),
         Mp_Info_Base    => MP.Mp_Info_Base,
         Mp_Flags        => MP.Flags,
         Cmdline_Text    => "",
         Rsdp_Physical   => Rsdp_Phys,
         Has_Rsdp        => Has_Rsdp,
         Boot_Timestamp  => Unix_Timestamp,
         Cpu_List        => Cpus (1 .. MP.Count),
         Bsp_Lapic_Id    => Bsp_Lapic,
         Entry_Address   => Entry_Address,
         Has_Entry_Point => Has_Entry,
         Selected_Paging_Mode => Paging_Mode,
         Ok              => Populate_Ok);

      if not Populate_Ok then
         Fatal ("building the Limine responses failed (unsupported paging mode?)");
      end if;
      Log_Value ("LIMINADE: paging mode ", Paging_Mode);
      if Has_Entry then
         Log_Value ("LIMINADE: entry point request ", Entry_Address);
      else
         Entry_Address := Kernel.Elf_Entry;
      end if;

      Switch_Page_Tables (Root);
      Log ("LIMINADE: paging enabled, jumping to the kernel");

      Jump_To_Kernel (Entry_Address, HHDM + Unsigned_64 (Stack_Phys) + Stack_Bytes);

      loop
         null;
      end loop;
   end Run_Boot;

   ----------
   -- Main --
   ----------

   procedure Main
     (Image_Handle : EFI.EFI_HANDLE;
      System_Table : EFI.EFI_SYSTEM_TABLE_ACCESS)
   is
      pragma Unreferenced (Image_Handle, System_Table);
   begin
      COM1.Initialize;
      COM1.Put_Line ("LIMINADE: Ada UEFI entry reached");
      Run_Boot (Image_Handle, System_Table);
   end Main;

end Liminade;
