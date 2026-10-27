with System;
with Interfaces; use Interfaces;

with Memory;
with EFI;
with EFI.Services;

package body Paging is

   use Memory;
   use type EFI.EFI_STATUS;

   PAGE_SIZE : constant Unsigned_64 := 16#1000#;
   PAGE_2M   : constant Unsigned_64 := 16#20_0000#;
   ADDR_MASK : constant Unsigned_64 := 16#000F_FFFF_FFFF_F000#;

   BIT_PRESENT : constant Unsigned_64 := 2#1#;
   BIT_WRITE   : constant Unsigned_64 := 2#10#;
   BIT_HUGE    : constant Unsigned_64 := 2#1000_0000#;
   BIT_NX      : constant Unsigned_64 := 16#8000_0000_0000_0000#;

   Pool_Base   : Unsigned_64 := 0;
   Pool_Pages  : Unsigned_64 := 0;
   Pool_Used   : Unsigned_64 := 0;
   Pool_Error  : Boolean := False;

   function Initialize (Page_Count : Unsigned_64) return Boolean is
      Phys : EFI.EFI_PHYSICAL_ADDRESS;
      St   : EFI.EFI_STATUS;
   begin
      St := EFI.Services.Allocate_Pages (EFI.Memory_Loader_Data, Page_Count, Phys);
      if St /= EFI.EFI_SUCCESS then
         return False;
      end if;
      Pool_Base := Unsigned_64 (Phys);
      Pool_Pages := Page_Count;
      Pool_Used := 0;
      Pool_Error := False;
      Zero (To_Address (Pool_Base), Page_Count * PAGE_SIZE);
      return True;
   end Initialize;

   function Alloc_Page return Unsigned_64 is
      Page : Unsigned_64;
   begin
      if Pool_Used >= Pool_Pages then
         Pool_Error := True;
         return 0;
      end if;
      Page := Pool_Base + Pool_Used * PAGE_SIZE;
      Pool_Used := Pool_Used + 1;
      Zero (To_Address (Page), PAGE_SIZE);
      return Page;
   end Alloc_Page;

   function Pool_Failed return Boolean is
   begin
      return Pool_Error;
   end Pool_Failed;

   function New_PML4 return Unsigned_64 is
   begin
      return Alloc_Page;
   end New_PML4;

   function Index (Virtual : Unsigned_64; Level : Natural) return Natural is
     (Natural (Shift_Right (Virtual, 12 + 9 * Level) and 16#1FF#));

   function Table_Of (Table_Entry : Unsigned_64) return Unsigned_64 is
     (Table_Entry and ADDR_MASK);

   --  Split a 2 MiB page entry in a page directory into a page table so a
   --  4 KiB mapping can be installed inside it.
   function Split_Huge (Table_Entry, Virtual : Unsigned_64) return Unsigned_64 is
      Pt      : constant Unsigned_64 := Alloc_Page;
      Base    : constant Unsigned_64 := Table_Of (Table_Entry);
      Flags   : constant Unsigned_64 := Table_Entry and (BIT_WRITE or BIT_NX);
   begin
      for I in 0 .. 511 loop
         Store64 (To_Address (Pt + Unsigned_64 (I) * 8),
                  (Base + Unsigned_64 (I) * PAGE_2M) or Flags or BIT_PRESENT);
      end loop;
      return Pt;
   end Split_Huge;

   procedure Map_4K
     (Root, Virtual, Physical : Unsigned_64;
      Writable                : Boolean;
      Executable              : Boolean)
   is
      Table : Unsigned_64 := Root;
      Table_Entry : Unsigned_64;
      Child : Unsigned_64;
      Slot  : Unsigned_64;
   begin
      for Level in reverse 1 .. 3 loop
         Slot := Table + Unsigned_64 (Index (Virtual, Level)) * 8;
         Table_Entry := Load64 (To_Address (Slot));
         if (Table_Entry and BIT_PRESENT) = 0 then
            Child := Alloc_Page;
            Store64 (To_Address (Slot), Child or BIT_WRITE or BIT_PRESENT);
            Table := Child;
         elsif (Table_Entry and BIT_HUGE) /= 0 then
            Child := Split_Huge (Table_Entry, Virtual);
            Store64 (To_Address (Slot), Child or BIT_WRITE or BIT_PRESENT);
            Table := Child;
         else
            Table := Table_Of (Table_Entry);
         end if;
      end loop;

      Slot := Table + Unsigned_64 (Index (Virtual, 0)) * 8;
      Table_Entry := (Physical and ADDR_MASK) or BIT_PRESENT;
      if Writable then
         Table_Entry := Table_Entry or BIT_WRITE;
      end if;
      if not Executable then
         Table_Entry := Table_Entry or BIT_NX;
      end if;
      Store64 (To_Address (Slot), Table_Entry);
   end Map_4K;

   procedure Map_2M
     (Root, Virtual, Physical : Unsigned_64;
      Writable                : Boolean;
      Executable              : Boolean)
   is
      Table : Unsigned_64 := Root;
      Table_Entry : Unsigned_64;
      Child : Unsigned_64;
      Slot  : Unsigned_64;
   begin
      for Level in reverse 2 .. 3 loop
         Slot := Table + Unsigned_64 (Index (Virtual, Level)) * 8;
         Table_Entry := Load64 (To_Address (Slot));
         if (Table_Entry and BIT_PRESENT) = 0 then
            Child := Alloc_Page;
            Store64 (To_Address (Slot), Child or BIT_WRITE or BIT_PRESENT);
            Table := Child;
         elsif (Table_Entry and BIT_HUGE) /= 0 then
            Child := Split_Huge (Table_Entry, Virtual);
            Store64 (To_Address (Slot), Child or BIT_WRITE or BIT_PRESENT);
            Table := Child;
         else
            Table := Table_Of (Table_Entry);
         end if;
      end loop;

      Slot := Table + Unsigned_64 (Index (Virtual, 1)) * 8;
      Table_Entry := (Physical and ADDR_MASK) or BIT_HUGE or BIT_PRESENT;
      if Writable then
         Table_Entry := Table_Entry or BIT_WRITE;
      end if;
      if not Executable then
         Table_Entry := Table_Entry or BIT_NX;
      end if;
      Store64 (To_Address (Slot), Table_Entry);
   end Map_2M;

   procedure Map_Range
     (Root, Virtual, Physical, Size : Unsigned_64;
      Writable                       : Boolean;
      Executable                     : Boolean)
   is
      V   : Unsigned_64 := Virtual and not 16#FFF#;
      P   : Unsigned_64 := Physical and not 16#FFF#;
      Endv : constant Unsigned_64 :=
        (Virtual + Size + 16#FFF#) and not 16#FFF#;
   begin
      --  4 KiB pages until the next 2 MiB boundary.
      while V < Endv and then (V and (PAGE_2M - 1)) /= 0 loop
         Map_4K (Root, V, P, Writable, Executable);
         V := V + PAGE_SIZE;
         P := P + PAGE_SIZE;
      end loop;

      --  2 MiB pages for the aligned interior.
      while V + PAGE_2M <= Endv
        and then (V and (PAGE_2M - 1)) = (P and (PAGE_2M - 1))
      loop
         Map_2M (Root, V, P, Writable, Executable);
         V := V + PAGE_2M;
         P := P + PAGE_2M;
      end loop;

      --  Trailing 4 KiB pages.
      while V < Endv loop
         Map_4K (Root, V, P, Writable, Executable);
         V := V + PAGE_SIZE;
         P := P + PAGE_SIZE;
      end loop;
   end Map_Range;

end Paging;
