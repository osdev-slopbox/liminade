--  Raw memory access helpers.
--
--  The firmware hands out untyped pointers (System.Address) and the Limine
--  request/response structures are described by byte offsets in the protocol
--  header, so liminade mostly pokes at memory through explicit offsets rather
--  than Ada record overlays.  This package keeps those pokes in one place.

with System;
with Interfaces; use Interfaces;

package Memory is
   pragma Preelaborate;

   ------------------------
   --  Address conversion
   ------------------------

   function To_Address (Value : Unsigned_64) return System.Address;
   function To_U64 (Addr : System.Address) return Unsigned_64;

   ------------------------
   --  Natural-sized loads
   ------------------------

   function Load64 (Addr : System.Address) return Unsigned_64;
   procedure Store64 (Addr : System.Address; Value : Unsigned_64);

   function Load32 (Addr : System.Address) return Unsigned_32;
   procedure Store32 (Addr : System.Address; Value : Unsigned_32);

   function Load16 (Addr : System.Address) return Unsigned_16;
   procedure Store16 (Addr : System.Address; Value : Unsigned_16);

   function Load8 (Addr : System.Address) return Unsigned_8;
   procedure Store8 (Addr : System.Address; Value : Unsigned_8);

   ---------------
   --  Block ops
   ---------------

   procedure Copy (Dst : System.Address; Src : System.Address; Length : Unsigned_64);
   procedure Zero (Dst : System.Address; Length : Unsigned_64);

   --  Byte-wise string compare of a NUL-terminated C string against an Ada
   --  string.  Returns True when equal.
   function C_String_Equals (Addr : System.Address; S : String) return Boolean;

   --  Copy an Ada string into Dst and append a NUL byte.  Returns the number
   --  of bytes written (excluding the NUL).
   function Store_String (Dst : System.Address; S : String) return Unsigned_64;

   --  Copy a NUL-terminated CHAR16 (UEFI) string into Dst as CHAR16,
   --  including the terminator.  Returns the number of CHAR16 written
   --  (including the NUL).
   function Store_Wide_String (Dst : System.Address; S : String) return Unsigned_64;

end Memory;
