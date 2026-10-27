--  Filesystem access through EFI_SIMPLE_FILE_SYSTEM_PROTOCOL.
--
--  Used to read the kernel ELF and the Limine modules off the ESP (or any
--  other volume the bootloader image was loaded from).

with System;
with Interfaces; use Interfaces;

with EFI;

package EFI.Files is

   --  Locate the volume the running image came from and open its root.
   function Open_Boot_Volume return Boolean;

   function Open (Path : String) return EFI_FILE_ACCESS;
   procedure Close (File : EFI_FILE_ACCESS);

   --  Query the size of an open file (EFI_FILE_INFO.FileSize).
   function Get_Size (File : EFI_FILE_ACCESS; Size : out Unsigned_64) return Boolean;

   --  Read exactly Size bytes (or up to EOF).  Size is updated with the
   --  number of bytes actually transferred.
   function Read (File : EFI_FILE_ACCESS; Buffer : System.Address;
                  Size : in out Unsigned_64) return Boolean;

   --  Read a whole file into a caller-supplied buffer.
   function Read_File (Path : String; Buffer : System.Address;
                       Max_Size : Unsigned_64; Size : out Unsigned_64) return Boolean;

   --  Open, size, allocate pages for and read a file.  Returns the physical
   --  address of the loaded copy (zero-padded to a 4 KiB boundary).
   function Load_File (Path : String; Physical_Address : out Unsigned_64;
                       Size : out Unsigned_64) return Boolean;

   function Exists (Path : String) return Boolean;

end EFI.Files;
