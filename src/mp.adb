--  Multiprocessor bring-up.  See src/mp.ads and src/mp_tramp.s.

with Interfaces; use Interfaces;
with System;

with COM1;
with EFI;
with EFI.Services;
with Memory;

package body MP is

   use Memory;
   use type System.Address;
   use type EFI.EFI_STATUS;

   Page_Size : constant Unsigned_64 := 4096;

   --  The trampoline must live below 1 MiB because SIPIs carry only a vector.
   Tramp_Vector     : constant Unsigned_32 := 16#08#;
   --  The 16-bit phase of the trampoline encodes 0x8000 as its segment, so
   --  the page cannot be relocated.
   Low_Candidates   : constant array (1 .. 1) of Unsigned_64 := (1 => 16#8000#);

   Ack_Magic : constant Unsigned_32 := 16#4D50_4B31#;   --  "MPK1"

   --  Local APIC registers (xAPIC MMIO offsets).
   Lapic_Tpr     : constant Unsigned_32 := 16#080#;
   Lapic_Svr     : constant Unsigned_32 := 16#0F0#;
   Lapic_Icr_Low : constant Unsigned_32 := 16#300#;
   Lapic_Icr_Hi  : constant Unsigned_32 := 16#310#;

   Icr_Delivery_Status : constant Unsigned_32 := 16#0000_1000#;
   Icr_Init_Assert     : constant Unsigned_32 := 16#0000_4500#;
   Icr_Sipi            : constant Unsigned_32 := 16#0000_0600#;

   Msr_Apic_Base : constant Unsigned_32 := 16#1B#;

   type Ioapic_Table is array (Positive range <>) of Unsigned_32;

   --  LVT registers masked by the protocol: timer, thermal, perf, LINT0,
   --  LINT1 and error.
   Lvt_Regs : constant array (1 .. 6) of Unsigned_32 :=
     (16#320#, 16#330#, 16#340#, 16#350#, 16#360#, 16#370#);

   ---------------------------------------------------------------
   --  Firmware / assembly shims
   ---------------------------------------------------------------

   function Read_Bsp_Lapic_Id return Unsigned_32;
   pragma Import (C, Read_Bsp_Lapic_Id, "read_bsp_lapic_id");

   function Read_Tsc return Unsigned_64;
   pragma Import (C, Read_Tsc, "read_tsc");

   function Read_Msr (Index : Unsigned_32) return Unsigned_64;
   pragma Import (C, Read_Msr, "read_msr");

   procedure Write_Msr (Index : Unsigned_32; Value : Unsigned_64);
   pragma Import (C, Write_Msr, "write_msr");

   procedure Out8 (Port : Unsigned_16; Value : Unsigned_8);
   pragma Import (C, Out8, "out8");

   --  Trampoline symbols (src/mp_tramp.s).  Only their addresses matter.
   Tramp_Start : Unsigned_8;
   pragma Import (C, Tramp_Start, "mp_tramp_start");
   Tramp_End : Unsigned_8;
   pragma Import (C, Tramp_End, "mp_tramp_end");
   Tramp_Cr3 : Unsigned_8;
   pragma Import (C, Tramp_Cr3, "mp_tramp_cr3");
   Tramp_Lapic : Unsigned_8;
   pragma Import (C, Tramp_Lapic, "mp_tramp_lapic");
   Tramp_Stack : Unsigned_8;
   pragma Import (C, Tramp_Stack, "mp_tramp_stack");
   Tramp_Mp_Info : Unsigned_8;
   pragma Import (C, Tramp_Mp_Info, "mp_tramp_mpinfo");
   Tramp_Ack : Unsigned_8;
   pragma Import (C, Tramp_Ack, "mp_tramp_ack");

   ---------------------------------------------------------------
   --  State
   ---------------------------------------------------------------

   N_Cpus     : Natural := 0;
   Cpu_List   : Cpu_Table (1 .. Max_Cpus);
   Infos_Phys : Unsigned_64 := 0;
   Tramp_Phys : Unsigned_64 := 0;
   Ap_Cpu     : Cpu_Table (1 .. Max_Cpus);
   Ap_Stack   : array (1 .. Max_Cpus) of Unsigned_64 := (others => 0);
   Ap_Count   : Natural := 0;
   Ready      : Boolean := False;
   Ticks_Per_Micro : Unsigned_64 := 1;
   Lapic_Base : Unsigned_64 := 16#FEE0_0000#;

   function Count return Natural is (N_Cpus);

   function Cpu (Index : Positive) return Cpu_Record is (Cpu_List (Index));

   function Mp_Info_Base return Unsigned_64 is (Infos_Phys);

   function Flags return Unsigned_32 is (0);

   ---------------------------------------------------------------
   --  ACPI table walk
   ---------------------------------------------------------------

   --  "APIC" in little-endian byte order.
   Sig_Apic : constant Unsigned_32 := 16#4349_5041#;

   --  Offset of a trampoline patch field inside the copied block.
   function Off (Sym : System.Address) return Unsigned_64 is
     (To_U64 (Sym) - To_U64 (Tramp_Start'Address));

   function Find_Acpi (Rsdp : Unsigned_64; Sig : Unsigned_32) return Unsigned_64 is
      Rev        : Unsigned_8;
      Root       : Unsigned_64;
      Length     : Unsigned_64;
      Entry_Size : Unsigned_64;
      Entries    : Unsigned_64;
   begin
      if Rsdp = 0 then
         return 0;
      end if;
      --  "RSD PTR " signature.
      if Load64 (To_Address (Rsdp)) /= 16#2052_5450_2044_5352# then
         return 0;
      end if;
      Rev := Load8 (To_Address (Rsdp + 15));
      if Rev >= 2 and then Load32 (To_Address (Rsdp + 20)) >= 36 then
         Root       := Load64 (To_Address (Rsdp + 24));
         Entry_Size := 8;
      else
         Root       := Unsigned_64 (Load32 (To_Address (Rsdp + 16)));
         Entry_Size := 4;
      end if;
      if Root = 0 then
         return 0;
      end if;
      Length := Unsigned_64 (Load32 (To_Address (Root + 4)));
      if Length < 36 then
         return 0;
      end if;
      Entries := (Length - 36) / Entry_Size;
      for I in 0 .. Entries loop
         exit when I = Entries;
         declare
            Slot : constant Unsigned_64 := Root + 36 + I * Entry_Size;
            Tbl : Unsigned_64;
         begin
            if Entry_Size = 8 then
               Tbl := Load64 (To_Address (Slot));
            else
               Tbl := Unsigned_64 (Load32 (To_Address (Slot)));
            end if;
            if Tbl /= 0 and then Load32 (To_Address (Tbl)) = Sig then
               return Tbl;
            end if;
         end;
      end loop;
      return 0;
   end Find_Acpi;

   procedure Scan_Madt
     (Madt         : Unsigned_64;
      Cpus         : out Cpu_Table;
      Count        : out Natural;
      Ioapics      : out Ioapic_Table;
      Ioapic_Count : out Natural)
   is
      Length : constant Unsigned_64 := Unsigned_64 (Load32 (To_Address (Madt + 4)));
      Stop   : constant Unsigned_64 := Madt + Length;
      Pos    : Unsigned_64 := Madt + 44;

      procedure Add (Processor_Id : Unsigned_32; Lapic_Id : Unsigned_32) is
      begin
         for I in 1 .. Count loop
            if Cpus (I).Lapic_Id = Lapic_Id then
               return;
            end if;
         end loop;
         if Count < Max_Cpus then
            Count := Count + 1;
            Cpus (Count) := (Processor_Id => Processor_Id, Lapic_Id => Lapic_Id);
         end if;
      end Add;
   begin
      Count        := 0;
      Ioapic_Count := 0;
      while Pos + 2 <= Stop loop
         declare
            Kind : constant Unsigned_8 := Load8 (To_Address (Pos));
            Elen : constant Unsigned_8 := Load8 (To_Address (Pos + 1));
         begin
            exit when Elen < 2 or else Pos + Unsigned_64 (Elen) > Stop;
            case Kind is
               when 0 =>
                  --  Processor Local APIC: uid (u8), apic id (u8), flags.
                  if (Load32 (To_Address (Pos + 4)) and 1) /= 0 then
                     Add (Unsigned_32 (Load8 (To_Address (Pos + 2))),
                          Unsigned_32 (Load8 (To_Address (Pos + 3))));
                  end if;
               when 9 =>
                  --  Processor Local x2APIC: uid (u32), id (u32), flags.
                  if (Load32 (To_Address (Pos + 12)) and 1) /= 0 then
                     Add (Load32 (To_Address (Pos + 4)),
                          Load32 (To_Address (Pos + 8)));
                  end if;
               when 1 =>
                  --  IO APIC: id, reserved, address (u32), gsi base.
                  if Ioapic_Count < Max_Ioapics then
                     Ioapic_Count := Ioapic_Count + 1;
                     Ioapics (Ioapic_Count) := Load32 (To_Address (Pos + 4));
                  end if;
               when others =>
                  null;
            end case;
            Pos := Pos + Unsigned_64 (Elen);
         end;
      end loop;
   end Scan_Madt;

   ---------------------------------------------------------------
   --  Interrupt controllers
   ---------------------------------------------------------------

   function Lapic_Read (Reg : Unsigned_32) return Unsigned_32 is
     (Load32 (To_Address (Lapic_Base + Unsigned_64 (Reg))));

   procedure Lapic_Write (Reg : Unsigned_32; Value : Unsigned_32) is
   begin
      Store32 (To_Address (Lapic_Base + Unsigned_64 (Reg)), Value);
   end Lapic_Write;

   --  Mask every IOAPIC redirection entry.  The protocol asks for the
   --  Fixed/Lowest/NMI/ExtINT entries to be masked; masking all of them is a
   --  superset and keeps the code simple.
   procedure Mask_Ioapic (Base : Unsigned_32) is
      Sel : constant System.Address := To_Address (Unsigned_64 (Base));
      Win : constant System.Address := To_Address (Unsigned_64 (Base) + 4);
      Max : Unsigned_32;
   begin
      if Base = 0 then
         return;
      end if;
      Store32 (Sel, 1);                          --  IOAPICVER
      Max := Shift_Right (Load32 (Win) and 16#00FF_0000#, 16);
      for Redir in 0 .. Max loop
         Store32 (Sel, 16#10# + Redir * 2);
         Store32 (Win, Load32 (Win) or 16#0001_0000#);
      end loop;
   end Mask_Ioapic;

   procedure Quiesce_Legacy (Ioapics : Ioapic_Table; Ioapic_Count : Natural) is
   begin
      Out8 (16#21#, 16#FF#);                     --  master PIC: all masked
      Out8 (16#A1#, 16#FF#);                     --  slave PIC: all masked
      for I in 1 .. Ioapic_Count loop
         Mask_Ioapic (Ioapics (I));
      end loop;
   end Quiesce_Legacy;

   --  Put the BSP's local APIC in the state the protocol requires.  x2APIC is
   --  explicitly disabled: the trampoline programs the APs through the xAPIC
   --  MMIO window, and the executable is free to enable x2APIC itself.
   procedure Init_Bsp_Lapic is
      Base_Msr : Unsigned_64;
   begin
      Base_Msr := Read_Msr (Msr_Apic_Base);
      Base_Msr := (Base_Msr and not Unsigned_64 (16#400#))
        or Unsigned_64 (16#800#);
      Write_Msr (Msr_Apic_Base, Base_Msr);
      Lapic_Base := Base_Msr and 16#000F_FFFF_FFFF_F000#;
      if Lapic_Base = 0 then
         Lapic_Base := 16#FEE0_0000#;
      end if;
      Lapic_Write (Lapic_Svr, 16#1FF#);
      Lapic_Write (Lapic_Tpr, 0);
      for I in Lvt_Regs'Range loop
         Lapic_Write (Lvt_Regs (I), Lapic_Read (Lvt_Regs (I)) or 16#0001_0000#);
      end loop;
   end Init_Bsp_Lapic;

   procedure Send_Ipi (Apic_Id : Unsigned_32; Icr_Low : Unsigned_32) is
   begin
      Lapic_Write (Lapic_Icr_Hi, Shift_Left (Apic_Id and 16#FF#, 24));
      Lapic_Write (Lapic_Icr_Low, Icr_Low);
      for I in 1 .. 1_000_000 loop
         exit when (Lapic_Read (Lapic_Icr_Low) and Icr_Delivery_Status) = 0;
      end loop;
   end Send_Ipi;

   ---------------------------------------------------------------
   --  AP startup
   ---------------------------------------------------------------

   procedure Fill_Info (Index : Natural; Item : Cpu_Record) is
      Pos : constant Unsigned_64 :=
        Infos_Phys + Unsigned_64 (Index) * Unsigned_64 (Mp_Info_Size);
   begin
      Store32 (To_Address (Pos + 0), Item.Processor_Id);
      Store32 (To_Address (Pos + 4), Item.Lapic_Id);
      Store64 (To_Address (Pos + 8), 0);
      Store64 (To_Address (Pos + 16), 0);
      Store64 (To_Address (Pos + 24), 0);
   end Fill_Info;

   function Patch_At (Tramp : Unsigned_64; Sym : System.Address)
     return System.Address is
     (To_Address (Tramp + Off (Sym)));

   --  Busy wait, calibrated against the firmware's Stall in Prepare.  Used
   --  for the INIT-SIPI timing, which happens after boot services are gone.
   procedure Delay_Micros (Us : Unsigned_64) is
      Started : constant Unsigned_64 := Read_Tsc;
      Limit   : constant Unsigned_64 := Us * Ticks_Per_Micro;
   begin
      while Read_Tsc - Started < Limit loop
         null;
      end loop;
   end Delay_Micros;

   procedure Prepare (Rsdp_Physical : Unsigned_64; Root : Unsigned_64) is
      All_Cpus     : Cpu_Table (1 .. Max_Cpus);
      Madt_Cpus    : Natural := 0;
      Ioapics      : Ioapic_Table (1 .. Max_Ioapics) := (others => 0);
      Ioapic_Count : Natural := 0;
      Madt         : Unsigned_64;
      Bsp_Id       : Unsigned_32;
      Bsp_Index    : Natural := 0;
      Tramp        : Unsigned_64 := 0;
      Info_Mem     : EFI.EFI_PHYSICAL_ADDRESS;
      Stack_Mem    : EFI.EFI_PHYSICAL_ADDRESS;
      Low_Mem      : EFI.EFI_PHYSICAL_ADDRESS;
      Status       : EFI.EFI_STATUS;
      Tramp_Size   : constant Unsigned_64 :=
        To_U64 (Tramp_End'Address) - To_U64 (Tramp_Start'Address);
   begin
      N_Cpus := 0;
      Infos_Phys := 0;
      Tramp_Phys := 0;
      Ap_Count := 0;
      Ready := False;
      Bsp_Id := Read_Bsp_Lapic_Id;

      Madt := Find_Acpi (Rsdp_Physical, Sig_Apic);
      if Madt /= 0 then
         Scan_Madt (Madt, All_Cpus, Madt_Cpus, Ioapics, Ioapic_Count);
         COM1.Put ("LIMINADE: MADT CPUs ");
         COM1.Put_Dec (Unsigned_64 (Madt_Cpus));
         COM1.Put_Line ("");
      else
         COM1.Put_Line ("LIMINADE: no MADT, single processor");
         Madt_Cpus := 1;
         All_Cpus (1) := (Processor_Id => 0, Lapic_Id => Bsp_Id);
      end if;
      if Madt_Cpus = 0 then
         Madt_Cpus := 1;
         All_Cpus (1) := (Processor_Id => 0, Lapic_Id => Bsp_Id);
      end if;

      for I in 1 .. Madt_Cpus loop
         if All_Cpus (I).Lapic_Id = Bsp_Id then
            Bsp_Index := I;
            exit;
         end if;
      end loop;
      if Bsp_Index = 0 then
         Bsp_Index := 1;
         All_Cpus (1) := (All_Cpus (1).Processor_Id, Bsp_Id);
      end if;

      Quiesce_Legacy (Ioapics, Ioapic_Count);
      Init_Bsp_Lapic;

      --  Release runs after ExitBootServices, where the firmware's Stall is
      --  no longer callable, yet INIT-SIPI still needs real delays.  Measure
      --  the TSC against a known Stall now and use it later.
      declare
         T0 : constant Unsigned_64 := Read_Tsc;
      begin
         Status := EFI.Services.Stall (10_000);
         Ticks_Per_Micro := Unsigned_64'Max (1, (Read_Tsc - T0) / 10_000);
      end;

      --  The mp_info array is shared with the executable for its whole
      --  lifetime: it must be plain, identity mapped memory.
      Status := EFI.Services.Allocate_Pages
        (EFI.Memory_Loader_Data,
         (Unsigned_64 (Max_Cpus) * Unsigned_64 (Mp_Info_Size) + Page_Size - 1)
           / Page_Size,
         Info_Mem);
      if Status /= EFI.EFI_SUCCESS then
         COM1.Put_Line ("LIMINADE: cannot allocate the MP info array");
         N_Cpus := 1;
         Cpu_List (1) := All_Cpus (Bsp_Index);
         return;
      end if;
      Infos_Phys := Unsigned_64 (Info_Mem);
      Zero (To_Address (Infos_Phys),
            Unsigned_64 (Max_Cpus) * Unsigned_64 (Mp_Info_Size));

      --  Copy the trampoline into low memory.
      for I in Low_Candidates'Range loop
         Status := EFI.Services.Allocate_Pages
           (EFI.Memory_Loader_Data, 1, Low_Mem,
            EFI.Allocate_Address,
            EFI.EFI_PHYSICAL_ADDRESS (Low_Candidates (I)));
         if Status = EFI.EFI_SUCCESS then
            Tramp := Unsigned_64 (Low_Mem);
            exit;
         end if;
      end loop;
      if Tramp = 0 or else Tramp_Size > Page_Size then
         COM1.Put_Line ("LIMINADE: cannot place the AP trampoline");
         N_Cpus := 1;
         Cpu_List (1) := All_Cpus (Bsp_Index);
         return;
      end if;
      Zero (To_Address (Tramp), Page_Size);
      Copy (To_Address (Tramp), Tramp_Start'Address, Tramp_Size);
      Tramp_Phys := Tramp;
      Store32 (Patch_At (Tramp, Tramp_Cr3'Address), Unsigned_32 (Root));
      Store32 (Patch_At (Tramp, Tramp_Lapic'Address), Unsigned_32 (Lapic_Base));

      --  Bootstrap processor first.
      N_Cpus := 1;
      Cpu_List (1) := All_Cpus (Bsp_Index);
      Fill_Info (0, Cpu_List (1));

      --  Reserve a stack for every other processor.  The mp_info slot is
      --  assigned at release time, when the number of usable processors is
      --  known.
      for I in 1 .. Madt_Cpus loop
         if I /= Bsp_Index and then Ap_Count < Max_Cpus - 1 then
            Status := EFI.Services.Allocate_Pages
              (EFI.Memory_Loader_Data, Ap_Stack_Pages, Stack_Mem);
            if Status /= EFI.EFI_SUCCESS then
               COM1.Put_Line ("LIMINADE: cannot allocate an AP stack");
            else
               Ap_Count := Ap_Count + 1;
               Ap_Cpu (Ap_Count) := All_Cpus (I);
               Ap_Stack (Ap_Count) := Unsigned_64 (Stack_Mem);
            end if;
         end if;
      end loop;

      Ready := True;
   end Prepare;

   procedure Release is
      Acked : Boolean;
   begin
      if not Ready then
         return;
      end if;

      for K in 1 .. Ap_Count loop
         if N_Cpus < Max_Cpus then
            declare
               Item : constant Cpu_Record := Ap_Cpu (K);
            begin
               Store64 (Patch_At (Tramp_Phys, Tramp_Stack'Address),
                        Ap_Stack (K)
                          + Unsigned_64 (Ap_Stack_Pages) * Page_Size);
               Store64 (Patch_At (Tramp_Phys, Tramp_Mp_Info'Address),
                        Infos_Phys
                          + Unsigned_64 (N_Cpus) * Unsigned_64 (Mp_Info_Size));
               Store32 (Patch_At (Tramp_Phys, Tramp_Ack'Address), 0);
               Fill_Info (N_Cpus, Item);

               Send_Ipi (Item.Lapic_Id, Icr_Init_Assert);
               Delay_Micros (10_000);
               Send_Ipi (Item.Lapic_Id, Icr_Sipi or Tramp_Vector);
               Delay_Micros (200);
               Send_Ipi (Item.Lapic_Id, Icr_Sipi or Tramp_Vector);

               Acked := False;
               for Try in 1 .. 100 loop
                  if Load32 (Patch_At (Tramp_Phys, Tramp_Ack'Address))
                       = Ack_Magic
                  then
                     Acked := True;
                     exit;
                  end if;
                  Delay_Micros (1_000);
               end loop;

               if Acked then
                  N_Cpus := N_Cpus + 1;
                  Cpu_List (N_Cpus) := Item;
                  COM1.Put ("LIMINADE: AP started, lapic id ");
                  COM1.Put_Dec (Unsigned_64 (Item.Lapic_Id));
                  COM1.Put_Line ("");
               else
                  COM1.Put ("LIMINADE: AP did not start, lapic id ");
                  COM1.Put_Dec (Unsigned_64 (Item.Lapic_Id));
                  COM1.Put_Line ("");
               end if;
            end;
         end if;
      end loop;

      COM1.Put ("LIMINADE: processors online ");
      COM1.Put_Dec (Unsigned_64 (N_Cpus));
      COM1.Put_Line ("");
   end Release;

end MP;
