with Ada.Unchecked_Conversion;
with System;
with Interfaces; use Interfaces;

with Memory;
with EFI;
with EFI.Services;

package body EFI.Files is

   use Memory;
   use type System.Address;

   File_Mode_Read : constant := 1;

   function As_Loaded_Image is new Ada.Unchecked_Conversion
     (System.Address, EFI.EFI_LOADED_IMAGE_ACCESS);
   function As_File_System is new Ada.Unchecked_Conversion
     (System.Address, EFI.EFI_SIMPLE_FILE_SYSTEM_ACCESS);

   Root : EFI_FILE_ACCESS := null;

   type Wide_Buffer is array (0 .. 511) of EFI.CHAR16;

   ----------------
   --  Internals
   ----------------

   function Path_To_Wide (Path : String; Buffer : out Wide_Buffer) return Boolean is
   begin
      if Path'Length > Buffer'Length - 1 then
         return False;
      end if;
      for I in Path'Range loop
         Buffer (I - Path'First) := EFI.CHAR16 (Character'Pos (Path (I)));
      end loop;
      Buffer (Path'Length) := 0;
      return True;
   end Path_To_Wide;

   ----------------------
   --  Open_Boot_Volume
   ----------------------

   function Open_Boot_Volume return Boolean is
      Li_Addr : System.Address;
      Fs_Addr : System.Address;
      Li      : EFI.EFI_LOADED_IMAGE_ACCESS;
      Fs      : EFI.EFI_SIMPLE_FILE_SYSTEM_ACCESS;
      St      : EFI.EFI_STATUS;
      New_Root : aliased EFI_FILE_ACCESS := null;
   begin
      St := EFI.Services.Handle_Protocol
        (EFI.Services.Image_Handle, EFI.LOADED_IMAGE_PROTOCOL_GUID, Li_Addr);
      if St /= EFI.EFI_SUCCESS or else Li_Addr = System.Null_Address then
         return False;
      end if;
      Li := As_Loaded_Image (Li_Addr);

      St := EFI.Services.Handle_Protocol
        (Li.Device_Handle, EFI.SIMPLE_FILE_SYSTEM_PROTOCOL_GUID, Fs_Addr);
      if St /= EFI.EFI_SUCCESS or else Fs_Addr = System.Null_Address then
         return False;
      end if;
      Fs := As_File_System (Fs_Addr);

      if Fs.Open_Volume = System.Null_Address then
         return False;
      end if;

      St := EFI.EFI_STATUS
        (EFI.MS_Call6 (Fs.Open_Volume,
                       To_Address (To_U64 (Fs_Addr)),
                       To_Address (To_U64 (New_Root'Address)),
                       System.Null_Address,
                       System.Null_Address,
                       System.Null_Address,
                       System.Null_Address));
      if St /= EFI.EFI_SUCCESS or else New_Root = null then
         return False;
      end if;
      Root := New_Root;
      return True;
   end Open_Boot_Volume;

   ------------
   --  Open
   ------------

   function Open (Path : String) return EFI_FILE_ACCESS is
      Wide : aliased Wide_Buffer;
      New_File : aliased EFI_FILE_ACCESS := null;
      St : EFI.EFI_STATUS;
   begin
      if Root = null or else not Path_To_Wide (Path, Wide) then
         return null;
      end if;
      St := EFI.EFI_STATUS
        (EFI.MS_Call6 (Root.Open,
                       To_Address (To_U64 (Root.all'Address)),
                       To_Address (To_U64 (New_File'Address)),
                       To_Address (To_U64 (Wide (0)'Address)),
                       To_Address (File_Mode_Read),
                       To_Address (0),
                       System.Null_Address));
      if St /= EFI.EFI_SUCCESS then
         return null;
      end if;
      return New_File;
   end Open;

   procedure Close (File : EFI_FILE_ACCESS) is
      St : Unsigned_64;
      pragma Unreferenced (St);
   begin
      if File = null then
         return;
      end if;
      St := EFI.MS_Call6 (File.Close,
                          To_Address (To_U64 (File.all'Address)),
                          System.Null_Address,
                          System.Null_Address,
                          System.Null_Address,
                          System.Null_Address,
                          System.Null_Address);
   end Close;

   ----------------
   --  Get_Size
   ----------------

   function Get_Size (File : EFI_FILE_ACCESS; Size : out Unsigned_64) return Boolean is
      Info      : aliased array (0 .. 511) of Unsigned_8;
      Info_Size : aliased Unsigned_64 := Info'Length;
      Guid      : aliased EFI.EFI_GUID := EFI.FILE_INFO_GUID;
      St        : EFI.EFI_STATUS;
   begin
      Size := 0;
      if File = null then
         return False;
      end if;
      St := EFI.EFI_STATUS
        (EFI.MS_Call6 (File.Get_Info,
                       To_Address (To_U64 (File.all'Address)),
                       To_Address (To_U64 (Guid'Address)),
                       To_Address (To_U64 (Info_Size'Address)),
                       To_Address (To_U64 (Info'Address)),
                       System.Null_Address,
                       System.Null_Address));
      if St /= EFI.EFI_SUCCESS then
         return False;
      end if;
      --  EFI_FILE_INFO: Size at 0, FileSize at 8.
      Size := Load64 (To_Address (To_U64 (Info'Address) + 8));
      return True;
   end Get_Size;

   ------------
   --  Read
   ------------

   function Read (File : EFI_FILE_ACCESS; Buffer : System.Address;
                  Size : in out Unsigned_64) return Boolean
   is
      Total : Unsigned_64 := 0;
      Chunk : Unsigned_64;
      St    : EFI.EFI_STATUS;
   begin
      if File = null then
         return False;
      end if;
      while Total < Size loop
         Chunk := Size - Total;
         St := EFI.EFI_STATUS
           (EFI.MS_Call6 (File.Read,
                          To_Address (To_U64 (File.all'Address)),
                          To_Address (To_U64 (Chunk'Address)),
                          To_Address (To_U64 (Buffer) + Total),
                          System.Null_Address,
                          System.Null_Address,
                          System.Null_Address));
         if St /= EFI.EFI_SUCCESS then
            Size := Total;
            return False;
         end if;
         Total := Total + Chunk;
         exit when Chunk = 0;
      end loop;
      Size := Total;
      return True;
   end Read;

   -----------------
   --  Read_File
   -----------------

   function Read_File (Path : String; Buffer : System.Address;
                       Max_Size : Unsigned_64; Size : out Unsigned_64) return Boolean
   is
      File : constant EFI_FILE_ACCESS := Open (Path);
      File_Size : Unsigned_64;
      Requested : Unsigned_64;
      Ok : Boolean;
   begin
      Size := 0;
      if File = null then
         return False;
      end if;
      if not Get_Size (File, File_Size) then
         Close (File);
         return False;
      end if;
      if File_Size > Max_Size then
         Close (File);
         return False;
      end if;
      Requested := File_Size;
      Ok := Read (File, Buffer, Requested);
      Close (File);
      if not Ok or else Requested /= File_Size then
         return False;
      end if;
      Size := File_Size;
      return True;
   end Read_File;

   -----------------
   --  Load_File
   -----------------

   function Load_File (Path : String; Physical_Address : out Unsigned_64;
                       Size : out Unsigned_64) return Boolean
   is
      File      : constant EFI_FILE_ACCESS := Open (Path);
      File_Size : Unsigned_64;
      Pages     : Unsigned_64;
      Phys      : EFI.EFI_PHYSICAL_ADDRESS;
      Requested : Unsigned_64;
      St        : EFI.EFI_STATUS;
      Ok        : Boolean;
   begin
      Physical_Address := 0;
      Size := 0;
      if File = null then
         return False;
      end if;
      if not Get_Size (File, File_Size) or else File_Size = 0 then
         Close (File);
         return False;
      end if;

      Pages := (File_Size + 16#FFF#) / 16#1000#;
      St := EFI.Services.Allocate_Pages (EFI.Memory_Loader_Data, Pages, Phys);
      if St /= EFI.EFI_SUCCESS then
         Close (File);
         return False;
      end if;

      Zero (To_Address (Unsigned_64 (Phys)), Pages * 16#1000#);

      Requested := File_Size;
      Ok := Read (File, To_Address (Unsigned_64 (Phys)), Requested);
      Close (File);
      if not Ok or else Requested /= File_Size then
         return False;
      end if;

      Physical_Address := Unsigned_64 (Phys);
      Size := File_Size;
      return True;
   end Load_File;

   --------------
   --  Exists
   --------------

   function Exists (Path : String) return Boolean is
      File : constant EFI_FILE_ACCESS := Open (Path);
   begin
      if File = null then
         return False;
      end if;
      Close (File);
      return True;
   end Exists;

end EFI.Files;
