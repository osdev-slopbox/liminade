/*  liminade UEFI entry shim.
 *
 *  The UEFI firmware calls the PE entry point with the MS x64 calling
 *  convention: ImageHandle in RCX, SystemTable in RDX.  GNAT compiles Ada
 *  with the System V ABI, which passes the first two arguments in RDI/RSI.
 *
 *  This stub is the only place where the two ABIs meet: copy the two
 *  arguments across and jump into the Ada main procedure.  If the Ada
 *  procedure ever returns, halt the machine.
 *
 *  A separate assembly file is required because Ada cannot declare the
 *  MS x64 convention and GNAT 16.2.0 has no inline-assembly pragma.
 */

        .section .text
        .globl  efi64_entry
        .type   efi64_entry, @function
efi64_entry:
        movq    %rcx, %rdi              /* ImageHandle  -> arg 1 */
        movq    %rdx, %rsi              /* SystemTable  -> arg 2 */
        andq    $-16, %rsp              /* keep the stack 16-byte aligned */
        call    efi_main
1:      cli
        hlt
        jmp     1b
        .size   efi64_entry, . - efi64_entry

        .section .note.GNU-stack,"",@progbits
