--  Minimal UEFI (EFI) bindings for liminade.
--
--  This package binds only the firmware structures liminade needs.  Every
--  record uses Convention => C so the layout matches the firmware's ABI
--  (MS x64 on x86_64) when the pointer values are dereferenced.
--
--  Scalar types follow the UEFI specification: EFI_STATUS is UINTN (64-bit
--  on x86_64), EFI_HANDLE is a pointer-sized opaque value.

with System;
with Interfaces; use Interfaces;

package EFI is
   pragma Preelaborate;

   ------------------------------
   --  Basic scalar types
   ------------------------------

   type EFI_STATUS is mod 2**64;

   EFI_SUCCESS           : constant EFI_STATUS := 16#0000_0000_0000_0000#;
   EFI_LOAD_ERROR        : constant EFI_STATUS := 16#8000_0000_0000_0001#;
   EFI_INVALID_PARAMETER : constant EFI_STATUS := 16#8000_0000_0000_0002#;
   EFI_UNSUPPORTED       : constant EFI_STATUS := 16#8000_0000_0000_0003#;
   EFI_BUFFER_TOO_SMALL  : constant EFI_STATUS := 16#8000_0000_0000_0005#;
   EFI_DEVICE_ERROR      : constant EFI_STATUS := 16#8000_0000_0000_0007#;
   EFI_OUT_OF_RESOURCES  : constant EFI_STATUS := 16#8000_0000_0000_0009#;
   EFI_NOT_FOUND         : constant EFI_STATUS := 16#8000_0000_0000_000E#;
   EFI_ABORTED           : constant EFI_STATUS := 16#8000_0000_0000_0015#;

   type EFI_HANDLE is new System.Address;
   type EFI_EVENT  is new System.Address;

   type EFI_BOOLEAN is mod 2**8;

   type CHAR8  is mod 2**8;
   type CHAR16 is mod 2**16;

   type CHAR16_PTR is access all CHAR16;
   type CHAR8_PTR  is access all CHAR8;

   type Unsigned_8_Array_8 is array (0 .. 7) of Unsigned_8;

   type EFI_GUID is record
      Data1 : Unsigned_32;
      Data2 : Unsigned_16;
      Data3 : Unsigned_16;
      Data4 : Unsigned_8_Array_8;
   end record with Convention => C;

   type EFI_TABLE_HEADER is record
      Signature   : Unsigned_64;
      Revision    : Unsigned_32;
      Header_Size : Unsigned_32;
      CRC32       : Unsigned_32;
      Reserved    : Unsigned_32;
   end record with Convention => C;

   ---------------------------------------------------------------
   --  Firmware calls
   --
   --  UEFI firmware uses the MS x64 calling convention, which GNAT cannot
   --  emit on this target.  Every function pointer obtained from a firmware
   --  table is therefore stored as a plain System.Address and invoked through
   --  ms_call6 (src/ms_abi.s), which moves the arguments into RCX/RDX/R8/R9
   --  and the stack before performing the call.
   --
   --  ms_call6 (Fn, A1 .. A6) returns the raw RAX value; unused arguments are
   --  passed as System.Null_Address.
   ---------------------------------------------------------------

   function MS_Call6
     (Fn : System.Address;
      A1 : System.Address;
      A2 : System.Address;
      A3 : System.Address;
      A4 : System.Address;
      A5 : System.Address;
      A6 : System.Address) return Unsigned_64;
   pragma Import (C, MS_Call6, "ms_call6");

   ---------------------------------------------------------------
   --  EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL
   --
   --  Reset           : EFI_STATUS (This, BOOLEAN ExtendedVerification)
   --  Output_String   : EFI_STATUS (This, CHAR16 *String)
   --  Test_String     : EFI_STATUS (This, CHAR16 *String)
   --  Query_Mode      : EFI_STATUS (This, UINTN Mode, UINTN *Cols, UINTN *Rows)
   --  Set_Mode        : EFI_STATUS (This, UINTN Mode)
   --  Set_Attribute   : EFI_STATUS (This, UINTN Attribute)
   --  Clear_Screen    : EFI_STATUS (This)
   --  Set_Cursor_Position : EFI_STATUS (This, UINTN Column, UINTN Row)
   --  Enable_Cursor   : EFI_STATUS (This, BOOLEAN Visible)
   ---------------------------------------------------------------

   type EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;
   type EFI_STOP_Access is access all EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;

   type EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL is record
      Reset               : System.Address;
      Output_String       : System.Address;
      Test_String         : System.Address;
      Query_Mode          : System.Address;
      Set_Mode            : System.Address;
      Set_Attribute       : System.Address;
      Clear_Screen        : System.Address;
      Set_Cursor_Position : System.Address;
      Enable_Cursor       : System.Address;
      Mode                : System.Address;
   end record with Convention => C;

   ---------------------------------------------------------------
   --  EFI_BOOT_SERVICES (only the members liminade uses are typed;
   --  unused entries are kept as raw pointers so the layout matches
   --  the firmware's table exactly)
   ---------------------------------------------------------------

   type EFI_TPL is mod 2**64;
   type EFI_MEMORY_TYPE is mod 2**32;
   type EFI_ALLOCATE_TYPE is mod 2**32;
   type EFI_PHYSICAL_ADDRESS is mod 2**64;
   type EFI_VIRTUAL_ADDRESS is mod 2**64;

   ---------------------------------------------------------------
   --  EFI_BOOT_SERVICES
   --
   --  Every member is a raw System.Address pointing at an MS-ABI function;
   --  call them through MS_Call6.  Signatures liminade needs (M2+):
   --
   --   Raise_TPL          : EFI_TPL (EFI_TPL NewTPL)
   --   Restore_TPL        : VOID (EFI_TPL OldTPL)
   --   Allocate_Pages     : EFI_STATUS (UINT32 Type, UINT32 MemoryType,
   --                                    UINTN Pages, EFI_PHYSICAL_ADDRESS *Memory)
   --   Free_Pages         : EFI_STATUS (EFI_PHYSICAL_ADDRESS Memory, UINTN Pages)
   --   Get_Memory_Map     : EFI_STATUS (UINTN *Size, VOID *Map, UINTN *Key,
   --                                    UINTN *DescSize, UINT32 *DescVersion)
   --   Allocate_Pool      : EFI_STATUS (UINT32 PoolType, UINTN Size, VOID **Buffer)
   --   Free_Pool          : EFI_STATUS (VOID *Buffer)
   --   Handle_Protocol    : EFI_STATUS (EFI_HANDLE, EFI_GUID *, VOID **Interface)
   --   Locate_Protocol    : EFI_STATUS (EFI_GUID *, VOID *Registration,
   --                                    VOID **Interface)
   --   Exit_Boot_Services : EFI_STATUS (EFI_HANDLE ImageHandle, UINTN MapKey)
   ---------------------------------------------------------------

   type EFI_BOOT_SERVICES is record
      Hdr                            : EFI_TABLE_HEADER;
      Raise_TPL                      : System.Address;
      Restore_TPL                    : System.Address;
      Allocate_Pages                 : System.Address;
      Free_Pages                     : System.Address;
      Get_Memory_Map                 : System.Address;
      Allocate_Pool                  : System.Address;
      Free_Pool                      : System.Address;
      Create_Event                   : System.Address;
      Set_Timer                      : System.Address;
      Wait_For_Event                 : System.Address;
      Signal_Event                   : System.Address;
      Close_Event                    : System.Address;
      Check_Event                    : System.Address;
      Install_Protocol_Interface     : System.Address;
      Reinstall_Protocol_Interface   : System.Address;
      Uninstall_Protocol_Interface   : System.Address;
      Handle_Protocol                : System.Address;
      Reserved                       : System.Address;
      Register_Protocol_Notify       : System.Address;
      Locate_Handle                  : System.Address;
      Locate_Device_Path             : System.Address;
      Install_Configuration_Table    : System.Address;
      Load_Image                     : System.Address;
      Start_Image                    : System.Address;
      Exit_Image                     : System.Address;
      Unload_Image                   : System.Address;
      Exit_Boot_Services             : System.Address;
      Get_Next_Monotonic_Count       : System.Address;
      Stall                          : System.Address;
      Set_Watchdog_Timer             : System.Address;
      Connect_Controller             : System.Address;
      Disconnect_Controller          : System.Address;
      Open_Protocol                  : System.Address;
      Close_Protocol                 : System.Address;
      Open_Protocol_Information      : System.Address;
      Protocols_Per_Handle           : System.Address;
      Locate_Handle_Buffer           : System.Address;
      Locate_Protocol                : System.Address;
      Install_Multiple_Protocol_Interfaces   : System.Address;
      Uninstall_Multiple_Protocol_Interfaces : System.Address;
      Calculate_CRC32                : System.Address;
      Copy_Mem                       : System.Address;
      Set_Mem                        : System.Address;
      Create_Event_Ex                : System.Address;
   end record with Convention => C;

   type EFI_BOOT_SERVICES_ACCESS is access all EFI_BOOT_SERVICES;

   ---------------------------------------------------------------
   --  EFI_SYSTEM_TABLE
   ---------------------------------------------------------------

   type EFI_SYSTEM_TABLE is record
      Hdr                     : EFI_TABLE_HEADER;
      Firmware_Vendor         : CHAR16_PTR;
      Firmware_Revision       : Unsigned_32;
      Padding                 : Unsigned_32;
      Console_In_Handle       : EFI_HANDLE;
      Con_In                  : System.Address;
      Console_Out_Handle      : EFI_HANDLE;
      Con_Out                 : EFI_STOP_Access;
      Standard_Error_Handle   : EFI_HANDLE;
      Std_Err                 : EFI_STOP_Access;
      Runtime_Services        : System.Address;
      Boot_Services           : EFI_BOOT_SERVICES_ACCESS;
      Number_Of_Table_Entries : Unsigned_64;
      Configuration_Table     : System.Address;
   end record with Convention => C;

   type EFI_SYSTEM_TABLE_ACCESS is access all EFI_SYSTEM_TABLE;

   ---------------------------------------------------------------
   --  Memory types / allocation
   ---------------------------------------------------------------

   Allocate_Any_Pages   : constant EFI_ALLOCATE_TYPE := 0;
   Allocate_Max_Address : constant EFI_ALLOCATE_TYPE := 1;
   Allocate_Address     : constant EFI_ALLOCATE_TYPE := 2;

   Memory_Reserved              : constant EFI_MEMORY_TYPE := 0;
   Memory_Loader_Code           : constant EFI_MEMORY_TYPE := 1;
   Memory_Loader_Data           : constant EFI_MEMORY_TYPE := 2;
   Memory_Boot_Services_Code    : constant EFI_MEMORY_TYPE := 3;
   Memory_Boot_Services_Data    : constant EFI_MEMORY_TYPE := 4;
   Memory_Runtime_Services_Code : constant EFI_MEMORY_TYPE := 5;
   Memory_Runtime_Services_Data : constant EFI_MEMORY_TYPE := 6;
   Memory_Conventional          : constant EFI_MEMORY_TYPE := 7;
   Memory_Unusable              : constant EFI_MEMORY_TYPE := 8;
   Memory_ACPI_Reclaim          : constant EFI_MEMORY_TYPE := 9;
   Memory_ACPI_NVS              : constant EFI_MEMORY_TYPE := 10;
   Memory_Mapped_IO             : constant EFI_MEMORY_TYPE := 11;
   Memory_Mapped_IO_Port_Space  : constant EFI_MEMORY_TYPE := 12;
   Memory_Pal_Code              : constant EFI_MEMORY_TYPE := 13;
   Memory_Persistent            : constant EFI_MEMORY_TYPE := 14;

   type EFI_MEMORY_DESCRIPTOR is record
      Memory_Type     : EFI_MEMORY_TYPE;
      Padding         : Unsigned_32;
      Physical_Start  : EFI_PHYSICAL_ADDRESS;
      Virtual_Start   : EFI_VIRTUAL_ADDRESS;
      Number_Of_Pages : Unsigned_64;
      Attribute       : Unsigned_64;
   end record with Convention => C;

   type EFI_MEMORY_DESCRIPTOR_ACCESS is access all EFI_MEMORY_DESCRIPTOR;

   type EFI_CONFIGURATION_TABLE is record
      Vendor_Guid  : EFI_GUID;
      Vendor_Table : System.Address;
   end record with Convention => C;

   type EFI_CONFIGURATION_TABLE_ACCESS is access all EFI_CONFIGURATION_TABLE;

   ---------------------------------------------------------------
   --  GUIDs
   ---------------------------------------------------------------

   ACPI_20_TABLE_GUID : constant EFI_GUID :=
     (Data1 => 16#8868_E871#, Data2 => 16#E4F1#, Data3 => 16#11D3#,
      Data4 => (16#BC#, 16#22#, 16#00#, 16#80#, 16#C7#, 16#3C#, 16#88#, 16#81#));

   ACPI_10_TABLE_GUID : constant EFI_GUID :=
     (Data1 => 16#EB9D_2D30#, Data2 => 16#2D88#, Data3 => 16#11D3#,
      Data4 => (16#9A#, 16#16#, 16#00#, 16#90#, 16#27#, 16#3F#, 16#C1#, 16#4D#));

   LOADED_IMAGE_PROTOCOL_GUID : constant EFI_GUID :=
     (Data1 => 16#5B1B_31A1#, Data2 => 16#9562#, Data3 => 16#11D2#,
      Data4 => (16#8E#, 16#3F#, 16#00#, 16#A0#, 16#C9#, 16#69#, 16#72#, 16#3B#));

   SIMPLE_FILE_SYSTEM_PROTOCOL_GUID : constant EFI_GUID :=
     (Data1 => 16#964E_5B22#, Data2 => 16#6459#, Data3 => 16#11D2#,
      Data4 => (16#8E#, 16#39#, 16#00#, 16#A0#, 16#C9#, 16#69#, 16#72#, 16#3B#));

   FILE_INFO_GUID : constant EFI_GUID :=
     (Data1 => 16#0957_6E92#, Data2 => 16#6D3F#, Data3 => 16#11D2#,
      Data4 => (16#8E#, 16#39#, 16#00#, 16#A0#, 16#C9#, 16#69#, 16#72#, 16#3B#));

   GRAPHICS_OUTPUT_PROTOCOL_GUID : constant EFI_GUID :=
     (Data1 => 16#9042_A9DE#, Data2 => 16#23DC#, Data3 => 16#4A38#,
      Data4 => (16#96#, 16#FB#, 16#7A#, 16#DE#, 16#D0#, 16#80#, 16#51#, 16#6A#));

   ---------------------------------------------------------------
   --  EFI_LOADED_IMAGE_PROTOCOL
   ---------------------------------------------------------------

   type EFI_LOADED_IMAGE_PROTOCOL is record
      Revision          : Unsigned_32;
      Padding           : Unsigned_32;
      Parent_Handle     : EFI_HANDLE;
      System_Table      : System.Address;
      Device_Handle     : EFI_HANDLE;
      File_Path         : System.Address;
      Reserved          : System.Address;
      Load_Options_Size : Unsigned_32;
      Padding2          : Unsigned_32;
      Load_Options      : System.Address;
      Image_Base        : System.Address;
      Image_Size        : Unsigned_64;
      Image_Code_Type   : EFI_MEMORY_TYPE;
      Image_Data_Type   : EFI_MEMORY_TYPE;
      Unload            : System.Address;
   end record with Convention => C;

   type EFI_LOADED_IMAGE_ACCESS is access all EFI_LOADED_IMAGE_PROTOCOL;

   ---------------------------------------------------------------
   --  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL / EFI_FILE_PROTOCOL
   ---------------------------------------------------------------

   type EFI_SIMPLE_FILE_SYSTEM_PROTOCOL is record
      Revision    : Unsigned_64;
      Open_Volume : System.Address;
   end record with Convention => C;

   type EFI_SIMPLE_FILE_SYSTEM_ACCESS is access all EFI_SIMPLE_FILE_SYSTEM_PROTOCOL;

   type EFI_FILE_PROTOCOL is record
      Revision     : Unsigned_64;
      Open         : System.Address;
      Close        : System.Address;
      Delete       : System.Address;
      Read         : System.Address;
      Write        : System.Address;
      Get_Position : System.Address;
      Set_Position : System.Address;
      Get_Info     : System.Address;
      Set_Info     : System.Address;
      Flush        : System.Address;
   end record with Convention => C;

   type EFI_FILE_ACCESS is access all EFI_FILE_PROTOCOL;

   --  EFI_FILE_INFO (variable length, the fixed part is 80 bytes).
   type EFI_FILE_INFO is record
      Size          : Unsigned_64;
      File_Size     : Unsigned_64;
      Physical_Size : Unsigned_64;
      Create_Time   : Unsigned_64;  --  actually EFI_TIME (16 bytes)
      Create_Time2  : Unsigned_64;
      Access_Time   : Unsigned_64;
      Access_Time2  : Unsigned_64;
      Modify_Time   : Unsigned_64;
      Modify_Time2  : Unsigned_64;
      Attribute     : Unsigned_64;
      --  CHAR16 FileName[] follows
   end record with Convention => C;

   type EFI_FILE_INFO_ACCESS is access all EFI_FILE_INFO;

   ---------------------------------------------------------------
   --  EFI_GRAPHICS_OUTPUT_PROTOCOL
   ---------------------------------------------------------------

   Pixel_Red_Green_Blue_Reserved_8_Bit : constant := 0;
   Pixel_Blue_Green_Red_Reserved_8_Bit : constant := 1;
   Pixel_Bit_Mask                      : constant := 2;

   type EFI_PIXEL_BITMASK is record
      Red_Reserved    : Unsigned_32;
      Green_Reserved  : Unsigned_32;
      Blue_Reserved   : Unsigned_32;
      Reserved_Reserved : Unsigned_32;
   end record with Convention => C;

   type EFI_GRAPHICS_OUTPUT_MODE_INFORMATION is record
      Version                : Unsigned_32;
      Horizontal_Resolution  : Unsigned_32;
      Vertical_Resolution    : Unsigned_32;
      Pixel_Format           : Unsigned_32;
      Pixel_Information      : EFI_PIXEL_BITMASK;
      Pixels_Per_Scan_Line   : Unsigned_32;
   end record with Convention => C;

   type EFI_GRAPHICS_OUTPUT_MODE_INFORMATION_ACCESS is
     access all EFI_GRAPHICS_OUTPUT_MODE_INFORMATION;

   type EFI_GOP_MODE is record
      Max_Mode          : Unsigned_32;
      Mode              : Unsigned_32;
      Info              : System.Address;
      Size_Of_Info      : Unsigned_64;
      Frame_Buffer_Base : EFI_PHYSICAL_ADDRESS;
      Frame_Buffer_Size : Unsigned_64;
   end record with Convention => C;

   type EFI_GOP_MODE_ACCESS is access all EFI_GOP_MODE;

   type EFI_GRAPHICS_OUTPUT_PROTOCOL is record
      Query_Mode : System.Address;
      Set_Mode   : System.Address;
      Blt        : System.Address;
      Mode       : EFI_GOP_MODE_ACCESS;
   end record with Convention => C;

   type EFI_GRAPHICS_OUTPUT_PROTOCOL_ACCESS is access all EFI_GRAPHICS_OUTPUT_PROTOCOL;

   ---------------------------------------------------------------
   --  EFI_TIME (Runtime Services GetTime)
   ---------------------------------------------------------------

   type EFI_TIME is record
      Year       : Unsigned_16;
      Month      : Unsigned_8;
      Day        : Unsigned_8;
      Hour       : Unsigned_8;
      Minute     : Unsigned_8;
      Second     : Unsigned_8;
      Pad1       : Unsigned_8;
      Nanosecond : Unsigned_32;
      Time_Zone  : Integer_16;
      Daylight   : Unsigned_8;
      Pad2       : Unsigned_8;
   end record with Convention => C;

end EFI;
