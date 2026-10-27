--  Graphics Output Protocol lookup (used for the Limine framebuffer
--  response).  Absent when the firmware boots headless, which is the normal
--  Terra/QEMU configuration.

with Interfaces; use Interfaces;

package EFI.GOP is

   type Framebuffer_Info is record
      Present          : Boolean := False;
      Physical_Address : Unsigned_64 := 0;
      Size             : Unsigned_64 := 0;
      Width            : Unsigned_64 := 0;
      Height           : Unsigned_64 := 0;
      Pitch            : Unsigned_64 := 0;
      Bpp              : Unsigned_16 := 0;
      Red_Size         : Unsigned_8 := 0;
      Red_Shift        : Unsigned_8 := 0;
      Green_Size       : Unsigned_8 := 0;
      Green_Shift      : Unsigned_8 := 0;
      Blue_Size        : Unsigned_8 := 0;
      Blue_Shift       : Unsigned_8 := 0;
   end record;

   function Get_Framebuffer return Framebuffer_Info;

end EFI.GOP;
