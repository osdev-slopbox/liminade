with Ada.Unchecked_Conversion;
with System;
with Interfaces; use Interfaces;

with Memory;
with EFI;
with EFI.Services;

package body EFI.GOP is

   use Memory;
   use type System.Address;

   function As_Gop is new Ada.Unchecked_Conversion
     (System.Address, EFI.EFI_GRAPHICS_OUTPUT_PROTOCOL_ACCESS);
   function As_Mode_Info is new Ada.Unchecked_Conversion
     (System.Address, EFI.EFI_GRAPHICS_OUTPUT_MODE_INFORMATION_ACCESS);

   function Trailing_Zeros (Value : Unsigned_32) return Unsigned_8 is
      X : Unsigned_32 := Value;
      N : Unsigned_8 := 0;
   begin
      if X = 0 then
         return 0;
      end if;
      while (X and 1) = 0 loop
         X := Shift_Right (X, 1);
         N := N + 1;
      end loop;
      return N;
   end Trailing_Zeros;

   function Bit_Count (Value : Unsigned_32) return Unsigned_8 is
      X : Unsigned_32 := Value;
      N : Unsigned_8 := 0;
   begin
      while X /= 0 loop
         N := N + Unsigned_8 (X and 1);
         X := Shift_Right (X, 1);
      end loop;
      return N;
   end Bit_Count;

   function Get_Framebuffer return Framebuffer_Info is
      Result : Framebuffer_Info;
      Addr   : System.Address;
      St     : EFI.EFI_STATUS;
      Gop    : EFI.EFI_GRAPHICS_OUTPUT_PROTOCOL_ACCESS;
      Mode   : EFI.EFI_GOP_MODE_ACCESS;
      Info   : EFI.EFI_GRAPHICS_OUTPUT_MODE_INFORMATION_ACCESS;
   begin
      St := EFI.Services.Locate_Protocol (EFI.GRAPHICS_OUTPUT_PROTOCOL_GUID, Addr);
      if St /= EFI.EFI_SUCCESS or else Addr = System.Null_Address then
         return Result;
      end if;

      Gop := As_Gop (Addr);
      if Gop.Mode = null then
         return Result;
      end if;
      Mode := Gop.Mode;
      if Mode.Info = System.Null_Address then
         return Result;
      end if;
      Info := As_Mode_Info (Mode.Info);

      Result.Present := True;
      Result.Physical_Address := Unsigned_64 (Mode.Frame_Buffer_Base);
      Result.Size := Mode.Frame_Buffer_Size;
      Result.Width := Unsigned_64 (Info.Horizontal_Resolution);
      Result.Height := Unsigned_64 (Info.Vertical_Resolution);
      Result.Pitch := Unsigned_64 (Info.Pixels_Per_Scan_Line) * 4;
      Result.Bpp := 32;

      case Info.Pixel_Format is
         when EFI.Pixel_Red_Green_Blue_Reserved_8_Bit =>
            Result.Red_Size := 8;   Result.Red_Shift := 16;
            Result.Green_Size := 8; Result.Green_Shift := 8;
            Result.Blue_Size := 8;  Result.Blue_Shift := 0;
         when EFI.Pixel_Blue_Green_Red_Reserved_8_Bit =>
            Result.Red_Size := 8;   Result.Red_Shift := 0;
            Result.Green_Size := 8; Result.Green_Shift := 8;
            Result.Blue_Size := 8;  Result.Blue_Shift := 16;
         when others =>
            --  Bit-mask formats: derive shifts from the GOP bitmask.
            declare
               R : constant Unsigned_32 := Info.Pixel_Information.Red_Reserved;
               G : constant Unsigned_32 := Info.Pixel_Information.Green_Reserved;
               B : constant Unsigned_32 := Info.Pixel_Information.Blue_Reserved;
            begin
               Result.Red_Shift := Trailing_Zeros (R);
               Result.Green_Shift := Trailing_Zeros (G);
               Result.Blue_Shift := Trailing_Zeros (B);
               Result.Red_Size := Bit_Count (R);
               Result.Green_Size := Bit_Count (G);
               Result.Blue_Size := Bit_Count (B);
            end;
      end case;

      return Result;
   end Get_Framebuffer;

end EFI.GOP;
