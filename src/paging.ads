--  4-level x86_64 page table construction.
--
--  liminade builds the address space the kernel starts in:
--    * an identity map of the low 4 GiB, so the bootloader keeps executing
--      across the CR3 switch and the kernel's early code has somewhere to go,
--    * the HHDM (all firmware memory-descriptor regions mapped at the HHDM
--      base), which is how response structures, modules and the framebuffer
--      are reached from the kernel,
--    * the kernel's own ELF segments at their link-time virtual addresses.

with Interfaces; use Interfaces;

package Paging is

   --  Allocate the page-table page pool.
   function Initialize (Page_Count : Unsigned_64) return Boolean;

   --  Allocate and zero a fresh top-level table (PML4).
   function New_PML4 return Unsigned_64;

   procedure Map_4K
     (Root, Virtual, Physical : Unsigned_64;
      Writable                : Boolean;
      Executable              : Boolean);

   procedure Map_2M
     (Root, Virtual, Physical : Unsigned_64;
      Writable                : Boolean;
      Executable              : Boolean);

   --  Map [Virtual, Virtual+Size) to [Physical, Physical+Size), using 2 MiB
   --  pages for aligned interiors and 4 KiB pages at the edges.
   procedure Map_Range
     (Root, Virtual, Physical, Size : Unsigned_64;
      Writable                       : Boolean;
      Executable                     : Boolean);

   function Pool_Failed return Boolean;

end Paging;
