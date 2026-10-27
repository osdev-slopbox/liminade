--  Multiprocessor support: ACPI/MADT CPU discovery, local APIC bring-up and
--  application-processor startup.
--
--  The AP trampoline itself lives in src/mp_tramp.s; this package copies it
--  into low memory, patches its parameter block and releases the processors
--  with INIT/SIPI IPIs.  Each AP parks in long mode on the bootloader's page
--  tables, polling its `limine_mp_info.goto_address` field until the
--  executable publishes an entry point.
--
--  Only the Limine protocol's minimum required machine state is set up here:
--  xAPIC mode, SVR = 0x1FF, TPR = 0, LVTs masked, PIC and IOAPIC IRQs masked.

with Interfaces; use Interfaces;
with System;

package MP is

   Max_Cpus    : constant := 64;
   Max_Ioapics : constant := 8;

   --  Size of the stack handed to each AP, per the Limine stack size feature.
   Ap_Stack_Pages : constant := 16;

   --  Limine `struct limine_mp_info` size and layout (rev 6, x86-64).
   Mp_Info_Size : constant := 32;

   --  Response flag: x2APIC is enabled.  liminade deliberately keeps the
   --  local APICs in xAPIC mode, so this is never set.
   Response_X2Apic : constant Unsigned_32 := 1;

   type Cpu_Record is record
      Processor_Id : Unsigned_32 := 0;   --  ACPI processor UID
      Lapic_Id     : Unsigned_32 := 0;   --  MADT APIC/x2APIC id
   end record;

   type Cpu_Table is array (Natural range <>) of Cpu_Record;

   ---------------------------------------------------------------
   --  Results (valid after Start)
   ---------------------------------------------------------------

   --  Number of processors the bootloader is handing to the executable,
   --  including the bootstrap processor.  Zero when Start has not run.
   function Count return Natural;

   function Cpu (Index : Positive) return Cpu_Record;

   --  Physical address of the first `limine_mp_info`; entry I is
   --  Mp_Info_Base + (I - 1) * Mp_Info_Size and belongs to Cpu (I).
   function Mp_Info_Base return Unsigned_64;

   --  Value for `limine_mp_response.flags`.
   function Flags return Unsigned_32;

   ---------------------------------------------------------------
   --  Bring-up
   ---------------------------------------------------------------

   --  Discover the processors from the ACPI MADT, quiesce the legacy
   --  interrupt controllers, initialise the BSP local APIC, allocate the
   --  mp_info array, the AP stacks and the low-memory trampoline, and
   --  calibrate the internal delay.  `Root` is the PML4 the APs must run on.
   --
   --  Prepare must run while the firmware's boot services are still
   --  available; it performs every allocation.  The processors themselves
   --  are not released until Release runs.
   procedure Prepare (Rsdp_Physical : Unsigned_64; Root : Unsigned_64);

   --  Send INIT-SIPI-SIPI to every processor found by Prepare and wait for
   --  it to park.  This must be called *after* ExitBootServices: firmware
   --  MP implementations re-park the APs in their own idle loop while
   --  boot services are being torn down.
   procedure Release;

end MP;
