--  Minimal ELF64 executable loader.
--
--  The kernel is a non-relocatable ET_EXEC image linked at its final virtual
--  addresses (0xffffffff800xxxxx for Terra).  The loader allocates one
--  contiguous physical region covering all PT_LOAD segments, copies the
--  segment contents there and reports the mapping so the paging code can
--  install it.

with Interfaces; use Interfaces;

package Kernel_Loader is

   Max_Segments : constant := 16;

   type Segment is record
      Virtual_Address  : Unsigned_64 := 0;
      Physical_Address : Unsigned_64 := 0;
      File_Offset      : Unsigned_64 := 0;
      File_Size        : Unsigned_64 := 0;
      Mem_Size         : Unsigned_64 := 0;
      Flags            : Unsigned_32 := 0;   --  PF_X=1, PF_W=2, PF_R=4
   end record;

   type Segment_Array is array (1 .. Max_Segments) of Segment;

   type Kernel is record
      Loaded         : Boolean := False;
      Physical_Base  : Unsigned_64 := 0;   --  physical address of Virtual_Base
      Virtual_Base   : Unsigned_64 := 0;   --  lowest PT_LOAD vaddr, page aligned
      Size           : Unsigned_64 := 0;   --  virtual span, page aligned
      Elf_Entry      : Unsigned_64 := 0;
      Segment_Count  : Natural := 0;
      Segments       : Segment_Array := (others => <>);
   end record;

   --  Read the ELF file, allocate its physical backing and copy the segments.
   function Load (Path : String; Result : out Kernel) return Boolean;

end Kernel_Loader;
