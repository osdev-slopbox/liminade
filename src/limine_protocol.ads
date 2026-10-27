--  Limine request scanning and response generation (protocol base revision 6).
--
--  Requests live in the loaded kernel image; the bootloader writes pointers to
--  response structures into them.  All response memory is allocated from a
--  physical arena supplied by the caller and advertised to the kernel through
--  the HHDM, since the kernel dereferences the pointers only after it has
--  switched to the bootloader's page tables.

with System;
with Interfaces; use Interfaces;

with EFI.GOP;
with Limine;

package Limine_Protocol is

   type Request_Kind is
     (Unknown,
      Bootloader_Info,
      Cmdline,
      Firmware_Type,
      Stack_Size,
      Hhdm,
      Framebuffer,
      Paging_Mode,
      Mp,
      Memmap,
      Entry_Point,
      Modules,
      Rsdp,
      Date_At_Boot,
      Dtb,
      Executable_File);

   type Request_Info is record
      Kind    : Request_Kind := Unknown;
      Address : Unsigned_64 := 0;   --  physical address of the request
   end record;

   Max_Requests : constant := 64;
   type Request_Array is array (1 .. Max_Requests) of Request_Info;

   type Scan_Result is record
      Count                 : Natural := 0;
      Requests              : Request_Array := (others => (Unknown, 0));
      Base_Revision_Address : Unsigned_64 := 0;
      Has_Base_Revision     : Boolean := False;
   end record;

   --  Walk an 8-byte-aligned loaded image region and record every Limine
   --  request found between the start and end markers.
   procedure Scan_Region
     (Base_Physical : Unsigned_64;
      Size          : Unsigned_64;
      Result        : in out Scan_Result);

   -----------------
   --  Module list
   -----------------

   Max_Path : constant := 128;

   type Module_Spec is record
      Path             : String (1 .. Max_Path) := (others => ' ');
      Path_Len         : Natural := 0;
      Physical_Address : Unsigned_64 := 0;
      Size             : Unsigned_64 := 0;
   end record;

   function Make_Module
     (Path : String; Physical_Address : Unsigned_64; Size : Unsigned_64)
      return Module_Spec;

   Empty_Module : constant Module_Spec :=
     (Path => (others => ' '), Path_Len => 0, Physical_Address => 0, Size => 0);

   type Module_Array is array (Natural range <>) of Module_Spec;

   ------------------
   --  CPU list (MP)
   ------------------

   type Cpu_Spec is record
      Processor_Id : Unsigned_32 := 0;   --  ACPI/CPUID processor id
      Lapic_Id     : Unsigned_32 := 0;
   end record;

   type Cpu_Array is array (Natural range <>) of Cpu_Spec;

   ------------------
   --  Response build
   ------------------

   procedure Populate
     (Requests       : Scan_Result;
      HHDM_Offset    : Unsigned_64;
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
      Ok             : out Boolean);

end Limine_Protocol;
