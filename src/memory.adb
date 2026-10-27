with Ada.Unchecked_Conversion;
with System;
with Interfaces; use Interfaces;
with System.Address_To_Access_Conversions;

package body Memory is

   use type System.Address;

   function Addr_Of is new Ada.Unchecked_Conversion (Unsigned_64, System.Address);
   function U64_Of is new Ada.Unchecked_Conversion (System.Address, Unsigned_64);

   function To_Address (Value : Unsigned_64) return System.Address is
   begin
      return Addr_Of (Value);
   end To_Address;

   function To_U64 (Addr : System.Address) return Unsigned_64 is
   begin
      return U64_Of (Addr);
   end To_U64;

   package U8_Conv  is new System.Address_To_Access_Conversions (Unsigned_8);
   package U16_Conv is new System.Address_To_Access_Conversions (Unsigned_16);
   package U32_Conv is new System.Address_To_Access_Conversions (Unsigned_32);
   package U64_Conv is new System.Address_To_Access_Conversions (Unsigned_64);

   ---------------
   --  Load/Store
   ---------------

   function Load64 (Addr : System.Address) return Unsigned_64 is
   begin
      return U64_Conv.To_Pointer (Addr).all;
   end Load64;

   procedure Store64 (Addr : System.Address; Value : Unsigned_64) is
   begin
      U64_Conv.To_Pointer (Addr).all := Value;
   end Store64;

   function Load32 (Addr : System.Address) return Unsigned_32 is
   begin
      return U32_Conv.To_Pointer (Addr).all;
   end Load32;

   procedure Store32 (Addr : System.Address; Value : Unsigned_32) is
   begin
      U32_Conv.To_Pointer (Addr).all := Value;
   end Store32;

   function Load16 (Addr : System.Address) return Unsigned_16 is
   begin
      return U16_Conv.To_Pointer (Addr).all;
   end Load16;

   procedure Store16 (Addr : System.Address; Value : Unsigned_16) is
   begin
      U16_Conv.To_Pointer (Addr).all := Value;
   end Store16;

   function Load8 (Addr : System.Address) return Unsigned_8 is
   begin
      return U8_Conv.To_Pointer (Addr).all;
   end Load8;

   procedure Store8 (Addr : System.Address; Value : Unsigned_8) is
   begin
      U8_Conv.To_Pointer (Addr).all := Value;
   end Store8;

   ---------------
   --  Block ops
   ---------------

   procedure Copy (Dst : System.Address; Src : System.Address; Length : Unsigned_64) is
      D : Unsigned_64 := To_U64 (Dst);
      S : Unsigned_64 := To_U64 (Src);
      N : Unsigned_64 := Length;
   begin
      --  Aligned 8-byte body first.
      while N >= 8 and then (D and 7) = 0 and then (S and 7) = 0 loop
         Store64 (To_Address (D), Load64 (To_Address (S)));
         D := D + 8;
         S := S + 8;
         N := N - 8;
      end loop;
      while N > 0 loop
         Store8 (To_Address (D), Load8 (To_Address (S)));
         D := D + 1;
         S := S + 1;
         N := N - 1;
      end loop;
   end Copy;

   procedure Zero (Dst : System.Address; Length : Unsigned_64) is
      D : Unsigned_64 := To_U64 (Dst);
      N : Unsigned_64 := Length;
   begin
      while N >= 8 and then (D and 7) = 0 loop
         Store64 (To_Address (D), 0);
         D := D + 8;
         N := N - 8;
      end loop;
      while N > 0 loop
         Store8 (To_Address (D), 0);
         D := D + 1;
         N := N - 1;
      end loop;
   end Zero;

   -------------------
   --  String helpers
   -------------------

   function C_String_Equals (Addr : System.Address; S : String) return Boolean is
      Base : constant Unsigned_64 := To_U64 (Addr);
      Idx  : Natural := S'First;
   begin
      if Addr = System.Null_Address then
         return False;
      end if;
      loop
         declare
            B : constant Unsigned_8 := Load8 (To_Address (Base + Unsigned_64 (Idx - S'First)));
         begin
            if Idx > S'Last then
               return B = 0;
            elsif B /= Unsigned_8 (Character'Pos (S (Idx))) then
               return False;
            end if;
         end;
         Idx := Idx + 1;
      end loop;
   end C_String_Equals;

   function Store_String (Dst : System.Address; S : String) return Unsigned_64 is
      Base : constant Unsigned_64 := To_U64 (Dst);
   begin
      for I in S'Range loop
         Store8 (To_Address (Base + Unsigned_64 (I - S'First)),
                 Unsigned_8 (Character'Pos (S (I))));
      end loop;
      Store8 (To_Address (Base + Unsigned_64 (S'Length)), 0);
      return Unsigned_64 (S'Length);
   end Store_String;

   function Store_Wide_String (Dst : System.Address; S : String) return Unsigned_64 is
      Base : constant Unsigned_64 := To_U64 (Dst);
   begin
      for I in S'Range loop
         Store16 (To_Address (Base + 2 * Unsigned_64 (I - S'First)),
                  Unsigned_16 (Character'Pos (S (I))));
      end loop;
      Store16 (To_Address (Base + 2 * Unsigned_64 (S'Length)), 0);
      return Unsigned_64 (S'Length) + 1;
   end Store_Wide_String;

end Memory;
