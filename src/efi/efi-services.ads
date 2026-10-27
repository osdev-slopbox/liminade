--  Thin wrappers over the EFI boot/runtime services liminade needs.
--
--  Every firmware function pointer is invoked through MS_Call6 (the MS x64
--  ABI trampoline); this package hides the address<->integer conversions and
--  the out-parameter plumbing behind ordinary Ada signatures.

with System;
with Interfaces; use Interfaces;

with EFI;

package EFI.Services is

   procedure Initialize (Image : EFI_HANDLE; System_Table : EFI_SYSTEM_TABLE_ACCESS);

   function Image_Handle return EFI_HANDLE;
   function System_Table return EFI_SYSTEM_TABLE_ACCESS;
   function Boot_Services return EFI_BOOT_SERVICES_ACCESS;
   function Runtime_Services return System.Address;

   function Allocate_Pages
     (Memory_Type  : EFI_MEMORY_TYPE;
      Page_Count   : Unsigned_64;
      Address      : out EFI_PHYSICAL_ADDRESS;
      Alloc_Type   : EFI_ALLOCATE_TYPE := Allocate_Any_Pages;
      Address_Hint : EFI_PHYSICAL_ADDRESS := 0) return EFI_STATUS;

   function Allocate_Pool
     (Pool_Type : EFI_MEMORY_TYPE;
      Size      : Unsigned_64;
      Buffer    : out System.Address) return EFI_STATUS;

   function Get_Memory_Map
     (Map_Buffer   : System.Address;
      Map_Size     : in out Unsigned_64;
      Map_Key      : out Unsigned_64;
      Desc_Size    : out Unsigned_64;
      Desc_Version : out Unsigned_32) return EFI_STATUS;

   function Exit_Boot_Services (Map_Key : Unsigned_64) return EFI_STATUS;

   function Handle_Protocol
     (Handle            : EFI_HANDLE;
      Guid              : EFI_GUID;
      Interface_Address : out System.Address) return EFI_STATUS;

   function Locate_Protocol
     (Guid              : EFI_GUID;
      Interface_Address : out System.Address) return EFI_STATUS;

   function Get_Time (Time : out EFI_TIME) return EFI_STATUS;

   function Stall (Microseconds : Unsigned_64) return EFI_STATUS;

   function Disable_Watchdog return EFI_STATUS;

end EFI.Services;
