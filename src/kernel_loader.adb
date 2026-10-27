with System;
with Interfaces; use Interfaces;

with Memory;
with EFI;
with EFI.Files;
with EFI.Services;

package body Kernel_Loader is

   use Memory;
   use type EFI.EFI_STATUS;

   PT_LOAD : constant := 1;

   ELF_MAGIC : constant Unsigned_32 := 16#464C457F#;  --  0x7F 'E' 'L' 'F'

   function Load (Path : String; Result : out Kernel) return Boolean is
      Temp_Phys : Unsigned_64 := 0;
      File_Size : Unsigned_64 := 0;
      Hdr       : Unsigned_64;
      Ph_Off    : Unsigned_64;
      Ph_Ent    : Unsigned_64;
      Ph_Num    : Unsigned_64;
      Min_Vaddr : Unsigned_64 := 16#FFFF_FFFF_FFFF_FFFF#;
      Max_Vaddr : Unsigned_64 := 0;
      Seg_Count : Natural := 0;
      Pages     : Unsigned_64;
      Phys_Base : EFI.EFI_PHYSICAL_ADDRESS;
      St        : EFI.EFI_STATUS;
      Result_Kernel : Kernel;
   begin
      Result := Result_Kernel;

      if not EFI.Files.Load_File (Path, Temp_Phys, File_Size) then
         return False;
      end if;
      if File_Size < 64 then
         return False;
      end if;

      Hdr := Temp_Phys;
      if Load32 (To_Address (Hdr)) /= ELF_MAGIC then
         return False;
      end if;
      if Load8 (To_Address (Hdr + 4)) /= 2 then   --  ELFCLASS64
         return False;
      end if;
      if Load8 (To_Address (Hdr + 5)) /= 1 then   --  ELFDATA2LSB
         return False;
      end if;
      if Load16 (To_Address (Hdr + 18)) /= 16#3E# then  --  EM_X86_64
         return False;
      end if;

      Ph_Off := Load64 (To_Address (Hdr + 32));
      Ph_Ent := Unsigned_64 (Load16 (To_Address (Hdr + 54)));
      Ph_Num := Unsigned_64 (Load16 (To_Address (Hdr + 56)));

      if Ph_Num = 0 or else Ph_Num > Unsigned_64 (Max_Segments) then
         return False;
      end if;
      if Ph_Off + Ph_Num * Ph_Ent > File_Size then
         return False;
      end if;

      --  First pass: virtual span and segment metadata.
      for I in 0 .. Ph_Num - 1 loop
         declare
            Ph     : constant Unsigned_64 := Hdr + Ph_Off + I * Ph_Ent;
            P_Type : constant Unsigned_32 := Load32 (To_Address (Ph));
            P_Flags : constant Unsigned_32 := Load32 (To_Address (Ph + 4));
            P_Off  : constant Unsigned_64 := Load64 (To_Address (Ph + 8));
            P_Vaddr : constant Unsigned_64 := Load64 (To_Address (Ph + 16));
            P_Filesz : constant Unsigned_64 := Load64 (To_Address (Ph + 32));
            P_Memsz : constant Unsigned_64 := Load64 (To_Address (Ph + 40));
         begin
            if P_Type = PT_LOAD and then P_Memsz > 0 then
               if P_Off + P_Filesz > File_Size then
                  return False;
               end if;
               Seg_Count := Seg_Count + 1;
               if Seg_Count > Max_Segments then
                  return False;
               end if;
               Result_Kernel.Segments (Seg_Count) :=
                 (Virtual_Address  => P_Vaddr,
                  Physical_Address => 0,
                  File_Offset      => P_Off,
                  File_Size        => P_Filesz,
                  Mem_Size         => P_Memsz,
                  Flags            => P_Flags);
               Min_Vaddr := Unsigned_64'Min (Min_Vaddr, P_Vaddr and not 16#FFF#);
               Max_Vaddr := Unsigned_64'Max
                 (Max_Vaddr, (P_Vaddr + P_Memsz + 16#FFF#) and not 16#FFF#);
            end if;
         end;
      end loop;

      if Seg_Count = 0 then
         return False;
      end if;

      Pages := (Max_Vaddr - Min_Vaddr) / 16#1000#;
      St := EFI.Services.Allocate_Pages (EFI.Memory_Loader_Data, Pages, Phys_Base);
      if St /= EFI.EFI_SUCCESS then
         return False;
      end if;

      Zero (To_Address (Unsigned_64 (Phys_Base)), Pages * 16#1000#);

      --  Second pass: copy the file contents into their final physical home.
      for I in 1 .. Seg_Count loop
         declare
            Seg : constant Segment := Result_Kernel.Segments (I);
            Dst : constant Unsigned_64 :=
              Unsigned_64 (Phys_Base) + (Seg.Virtual_Address - Min_Vaddr);
         begin
            if Seg.File_Size > 0 then
               Copy (To_Address (Dst), To_Address (Hdr + Seg.File_Offset), Seg.File_Size);
            end if;
         end;
      end loop;

      for I in 1 .. Seg_Count loop
         Result_Kernel.Segments (I).Physical_Address :=
           Unsigned_64 (Phys_Base) + (Result_Kernel.Segments (I).Virtual_Address - Min_Vaddr);
      end loop;

      Result_Kernel.Loaded := True;
      Result_Kernel.Physical_Base := Unsigned_64 (Phys_Base);
      Result_Kernel.Virtual_Base := Min_Vaddr;
      Result_Kernel.Size := Max_Vaddr - Min_Vaddr;
      Result_Kernel.Elf_Entry := Load64 (To_Address (Hdr + 24));
      Result_Kernel.Segment_Count := Seg_Count;
      Result := Result_Kernel;
      return True;
   end Load;

end Kernel_Loader;
