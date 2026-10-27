--  liminade - a Limine-compatible UEFI bootloader written in Ada.
--
--  Milestone 1 entry point: prove the Ada -> ELF -> PE32+ pipeline by
--  reporting through the UEFI console and the COM1 debug UART.
--
--  Main is called by the efi64_entry shim (src/efi64_entry.s), which bridges
--  the MS x64 UEFI calling convention (RCX/RDX) to the System V ABI used by
--  GNAT (RDI/RSI).  The export lives in the spec so it can be applied before
--  the body, as GNAT requires.

with EFI;

package Liminade is

   procedure Main
     (Image_Handle : EFI.EFI_HANDLE;
      System_Table : EFI.EFI_SYSTEM_TABLE_ACCESS);

   pragma Export (C, Main, "efi_main");

end Liminade;
