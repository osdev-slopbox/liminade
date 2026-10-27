--  COM1 (16550 UART) debug output.
--
--  Early bring-up output that does not depend on any firmware console
--  device, so it works even when QEMU/OVMF run headless (-display none).
--  The port I/O is performed by two tiny assembly helpers (out8/in8);
--  GNAT 16.2.0 has no inline-assembly pragma.

with Interfaces; use Interfaces;

package COM1 is
   pragma Preelaborate;

   --  Program the UART: 115200 baud, 8N1, FIFO on.
   procedure Initialize;

   --  Emit one character (waits for the transmit holding register to drain).
   procedure Put (C : Character);

   --  Emit a string.
   procedure Put (S : String);

   --  Emit a string followed by CR LF.
   procedure Put_Line (S : String);

   --  Emit Value as "0x" followed by 16 hexadecimal digits.
   procedure Put_Hex (Value : Unsigned_64);

   --  Emit Value in decimal.
   procedure Put_Dec (Value : Unsigned_64);

end COM1;
