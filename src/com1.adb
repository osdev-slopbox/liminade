with Interfaces; use Interfaces;

package body COM1 is

   Base : constant Unsigned_16 := 16#3F8#;

   --  Port I/O helpers, implemented in src/com1_io.s.
   procedure Out8 (Port : Unsigned_16; Value : Unsigned_8);
   pragma Import (C, Out8, "out8");

   function In8 (Port : Unsigned_16) return Unsigned_8;
   pragma Import (C, In8, "in8");

   --  Line status register: bit 5 (THRE) set when we may send a byte.
   LSR_THRE : constant Unsigned_8 := 16#20#;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize is
   begin
      Out8 (Base + 1, 16#00#);   --  disable interrupts
      Out8 (Base + 3, 16#80#);   --  DLAB on
      Out8 (Base + 0, 16#01#);   --  divisor = 1 -> 115200 baud
      Out8 (Base + 1, 16#00#);
      Out8 (Base + 3, 16#03#);   --  8 data bits, no parity, 1 stop, DLAB off
      Out8 (Base + 2, 16#C7#);   --  FIFO enable + clear, 14-byte threshold
      Out8 (Base + 4, 16#0B#);   --  DTR | RTS | OUT2
   end Initialize;

   ---------
   -- Put --
   ---------

   procedure Put (C : Character) is
      Spins : Natural := 0;
   begin
      --  Bounded wait so a missing/odd UART can never hang the bootloader.
      while (In8 (Base + 5) and LSR_THRE) = 0 and then Spins < 1_000_000 loop
         Spins := Spins + 1;
      end loop;

      Out8 (Base, Unsigned_8 (Character'Pos (C)));
   end Put;

   procedure Put (S : String) is
   begin
      for C of S loop
         Put (C);
      end loop;
   end Put;

   --------------
   -- Put_Line --
   --------------

   procedure Put_Line (S : String) is
   begin
      Put (S);
      Put (Character'Val (13));
      Put (Character'Val (10));
   end Put_Line;

   -------------
   -- Put_Hex --
   -------------

   procedure Put_Hex (Value : Unsigned_64) is
      Hex_Digits : constant String := "0123456789ABCDEF";
      Nibble : Unsigned_64;
   begin
      Put ("0x");
      for Shift in reverse 0 .. 15 loop
         Nibble := Unsigned_64 (Shift_Right (Value, Shift * 4)) and 16#F#;
         Put (Hex_Digits (Natural (Nibble) + 1));
      end loop;
   end Put_Hex;

   -------------
   -- Put_Dec --
   -------------

   procedure Put_Dec (Value : Unsigned_64) is
      Buf : String (1 .. 20);
      Pos : Natural := Buf'Last;
      V   : Unsigned_64 := Value;
   begin
      if V = 0 then
         Put ('0');
         return;
      end if;
      while V > 0 and then Pos >= Buf'First loop
         Buf (Pos) := Character'Val (Natural (V mod 10) + Character'Pos ('0'));
         V := V / 10;
         Pos := Pos - 1;
      end loop;
      Put (Buf (Pos + 1 .. Buf'Last));
   end Put_Dec;

end COM1;
