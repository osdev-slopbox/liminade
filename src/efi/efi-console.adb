with System;
with Interfaces; use Interfaces;

package body EFI.Console is

   use type System.Address;

   Max_Chars : constant := 255;

   type Char16_Buffer is array (0 .. Max_Chars) of CHAR16;

   ---------
   -- Put --
   ---------

   procedure Put (Device : EFI_STOP_Access; Text : String) is
      Buffer : Char16_Buffer;
      Last   : Natural := 0;
      Status : Unsigned_64;
      pragma Unreferenced (Status);
   begin
      if Device = null or else Device.Output_String = System.Null_Address then
         return;
      end if;

      for C of Text loop
         exit when Last = Max_Chars;
         Buffer (Last) := CHAR16 (Character'Pos (C));
         Last := Last + 1;
      end loop;
      Buffer (Last) := 0;

      --  ConOut->OutputString (This, String), called with the MS x64 ABI.
      Status := MS_Call6
        (Device.Output_String,
         Device.all'Address,
         Buffer (0)'Address,
         System.Null_Address,
         System.Null_Address,
         System.Null_Address,
         System.Null_Address);
   end Put;

   --------------
   -- Put_Line --
   --------------

   procedure Put_Line (Device : EFI_STOP_Access; Text : String) is
   begin
      Put (Device, Text);
      Put (Device, Character'Val (13) & Character'Val (10));
   end Put_Line;

end EFI.Console;
