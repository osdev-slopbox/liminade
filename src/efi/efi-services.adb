with System;
with Interfaces; use Interfaces;

with Memory;
with EFI;

package body EFI.Services is

   use Memory;
   use type System.Address;

   BS : EFI_BOOT_SERVICES_ACCESS := null;
   ST : EFI_SYSTEM_TABLE_ACCESS := null;
   IH : EFI_HANDLE := EFI_HANDLE (System.Null_Address);
   RT : System.Address := System.Null_Address;

   function Arg (Value : Unsigned_64) return System.Address is
     (Memory.To_Address (Value));

   function Arg (Value : EFI_MEMORY_TYPE) return System.Address is
     (Memory.To_Address (Unsigned_64 (Value)));

   function Arg (Value : EFI_ALLOCATE_TYPE) return System.Address is
     (Memory.To_Address (Unsigned_64 (Value)));

   procedure Initialize (Image : EFI_HANDLE; System_Table : EFI_SYSTEM_TABLE_ACCESS) is
   begin
      IH := Image;
      ST := System_Table;
      if System_Table /= null then
         BS := System_Table.Boot_Services;
         RT := System_Table.Runtime_Services;
      end if;
   end Initialize;

   function Image_Handle return EFI_HANDLE is
   begin
      return IH;
   end Image_Handle;

   function System_Table return EFI_SYSTEM_TABLE_ACCESS is
   begin
      return ST;
   end System_Table;

   function Boot_Services return EFI_BOOT_SERVICES_ACCESS is
   begin
      return BS;
   end Boot_Services;

   function Runtime_Services return System.Address is
   begin
      return RT;
   end Runtime_Services;

   -------------------
   --  Allocation
   -------------------

   function Allocate_Pages
     (Memory_Type  : EFI_MEMORY_TYPE;
      Page_Count   : Unsigned_64;
      Address      : out EFI_PHYSICAL_ADDRESS;
      Alloc_Type   : EFI_ALLOCATE_TYPE := Allocate_Any_Pages;
      Address_Hint : EFI_PHYSICAL_ADDRESS := 0) return EFI_STATUS
   is
      Phys : aliased EFI_PHYSICAL_ADDRESS := Address_Hint;
      St   : Unsigned_64;
   begin
      if BS = null then
         Address := 0;
         return EFI_UNSUPPORTED;
      end if;
      St := MS_Call6 (BS.Allocate_Pages,
                      Arg (Alloc_Type),
                      Arg (Memory_Type),
                      Arg (Page_Count),
                      Arg (To_U64 (Phys'Address)),
                      System.Null_Address,
                      System.Null_Address);
      Address := Phys;
      return EFI_STATUS (St);
   end Allocate_Pages;

   function Allocate_Pool
     (Pool_Type : EFI_MEMORY_TYPE;
      Size      : Unsigned_64;
      Buffer    : out System.Address) return EFI_STATUS
   is
      Buf : aliased System.Address := System.Null_Address;
      St  : Unsigned_64;
   begin
      if BS = null then
         Buffer := System.Null_Address;
         return EFI_UNSUPPORTED;
      end if;
      St := MS_Call6 (BS.Allocate_Pool,
                      Arg (Pool_Type),
                      Arg (Size),
                      Arg (To_U64 (Buf'Address)),
                      System.Null_Address,
                      System.Null_Address,
                      System.Null_Address);
      Buffer := Buf;
      return EFI_STATUS (St);
   end Allocate_Pool;

   function Get_Memory_Map
     (Map_Buffer   : System.Address;
      Map_Size     : in out Unsigned_64;
      Map_Key      : out Unsigned_64;
      Desc_Size    : out Unsigned_64;
      Desc_Version : out Unsigned_32) return EFI_STATUS
   is
      St : Unsigned_64;
   begin
      if BS = null then
         return EFI_UNSUPPORTED;
      end if;
      St := MS_Call6 (BS.Get_Memory_Map,
                      Arg (To_U64 (Map_Size'Address)),
                      Arg (To_U64 (Map_Buffer)),
                      Arg (To_U64 (Map_Key'Address)),
                      Arg (To_U64 (Desc_Size'Address)),
                      Arg (To_U64 (Desc_Version'Address)),
                      System.Null_Address);
      return EFI_STATUS (St);
   end Get_Memory_Map;

   function Exit_Boot_Services (Map_Key : Unsigned_64) return EFI_STATUS is
      St : Unsigned_64;
   begin
      if BS = null then
         return EFI_UNSUPPORTED;
      end if;
      St := MS_Call6 (BS.Exit_Boot_Services,
                      Arg (To_U64 (System.Address (IH))),
                      Arg (Map_Key),
                      System.Null_Address,
                      System.Null_Address,
                      System.Null_Address,
                      System.Null_Address);
      return EFI_STATUS (St);
   end Exit_Boot_Services;

   ----------------------
   --  Protocol lookup
   ----------------------

   function Handle_Protocol
     (Handle            : EFI_HANDLE;
      Guid              : EFI_GUID;
      Interface_Address : out System.Address) return EFI_STATUS
   is
      G   : aliased EFI_GUID := Guid;
      Ifc : aliased System.Address := System.Null_Address;
      St  : Unsigned_64;
   begin
      if BS = null then
         Interface_Address := System.Null_Address;
         return EFI_UNSUPPORTED;
      end if;
      St := MS_Call6 (BS.Handle_Protocol,
                      Arg (To_U64 (System.Address (Handle))),
                      Arg (To_U64 (G'Address)),
                      Arg (To_U64 (Ifc'Address)),
                      System.Null_Address,
                      System.Null_Address,
                      System.Null_Address);
      Interface_Address := Ifc;
      return EFI_STATUS (St);
   end Handle_Protocol;

   function Locate_Protocol
     (Guid              : EFI_GUID;
      Interface_Address : out System.Address) return EFI_STATUS
   is
      G   : aliased EFI_GUID := Guid;
      Ifc : aliased System.Address := System.Null_Address;
      St  : Unsigned_64;
   begin
      if BS = null then
         Interface_Address := System.Null_Address;
         return EFI_UNSUPPORTED;
      end if;
      St := MS_Call6 (BS.Locate_Protocol,
                      Arg (To_U64 (G'Address)),
                      System.Null_Address,
                      Arg (To_U64 (Ifc'Address)),
                      System.Null_Address,
                      System.Null_Address,
                      System.Null_Address);
      Interface_Address := Ifc;
      return EFI_STATUS (St);
   end Locate_Protocol;

   ---------------
   --  Runtime
   ---------------

   function Get_Time (Time : out EFI_TIME) return EFI_STATUS is
      Tmp : aliased EFI_TIME := (others => <>);
      St  : Unsigned_64;
      Fn  : System.Address;
   begin
      if RT = System.Null_Address then
         Time := Tmp;
         return EFI_UNSUPPORTED;
      end if;
      --  EFI_RUNTIME_SERVICES: Hdr (24 bytes) then the GetTime pointer.
      Fn := To_Address (Load64 (To_Address (To_U64 (RT) + 24)));
      St := MS_Call6 (Fn,
                      Arg (To_U64 (RT)),
                      Arg (To_U64 (Tmp'Address)),
                      System.Null_Address,
                      System.Null_Address,
                      System.Null_Address,
                      System.Null_Address);
      Time := Tmp;
      return EFI_STATUS (St);
   end Get_Time;

   function Stall (Microseconds : Unsigned_64) return EFI_STATUS is
      St : Unsigned_64;
   begin
      if BS = null then
         return EFI_UNSUPPORTED;
      end if;
      St := MS_Call6 (BS.Stall,
                      Arg (Microseconds),
                      System.Null_Address,
                      System.Null_Address,
                      System.Null_Address,
                      System.Null_Address,
                      System.Null_Address);
      return EFI_STATUS (St);
   end Stall;

   function Disable_Watchdog return EFI_STATUS is
      St : Unsigned_64;
   begin
      if BS = null then
         return EFI_UNSUPPORTED;
      end if;
      --  SetWatchdogTimer (Timeout = 0, WatchdogCode, DataSize, Data, ...)
      St := MS_Call6 (BS.Set_Watchdog_Timer,
                      Arg (Unsigned_64'(0)),
                      Arg (Unsigned_64'(0)),
                      Arg (Unsigned_64'(0)),
                      System.Null_Address,
                      System.Null_Address,
                      System.Null_Address);
      return EFI_STATUS (St);
   end Disable_Watchdog;

end EFI.Services;
