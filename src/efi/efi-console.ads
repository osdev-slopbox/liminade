--  Convenience wrappers around EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL.
--
--  All output goes through the firmware's ConOut device (a CHAR16 string
--  protocol); there is deliberately no dependency on Ada.Text_IO, the
--  program is freestanding.

package EFI.Console is

   --  Write Text to Device, without a trailing newline.
   --  Does nothing if Device is null or has no OutputString member.
   procedure Put (Device : EFI_STOP_Access; Text : String);

   --  Write Text followed by CR LF.
   procedure Put_Line (Device : EFI_STOP_Access; Text : String);

end EFI.Console;
