/*  liminade MS-x64 firmware call trampoline.
 *
 *  UEFI firmware functions use the MS x64 calling convention (RCX, RDX, R8, R9
 *  for the first four arguments, further arguments on the stack, caller
 *  allocated 32-byte shadow space).  GNAT on Linux can only emit the System V
 *  convention, so every call into firmware goes through ms_call6, which
 *  reshuffles the registers and performs the call.
 *
 *  System V entry state:
 *      RDI = function pointer
 *      RSI = arg1, RDX = arg2, RCX = arg3, R8 = arg4, R9 = arg5
 *      [RSP+8] = arg6
 *
 *  The return value stays in RAX, exactly where SysV expects it.
 */

        .section .text
        .globl  ms_call6
        .type   ms_call6, @function
ms_call6:
        movq    %rdi, %r11              /* function pointer (scratch) */
        movq    %rcx, %r10              /* stash arg3 (scratch) */

        subq    $0x38, %rsp             /* 32-byte shadow space + 2 stack args */
        movq    %r9, 0x20(%rsp)         /* arg5 -> stack */
        movq    0x40(%rsp), %rax        /* arg6 (was [rsp+8] before sub) */
        movq    %rax, 0x28(%rsp)

        movq    %rsi, %rcx              /* arg1 */
        /* arg2 is already in RDX */
        movq    %r8, %r9                /* arg4 */
        movq    %r10, %r8               /* arg3 */

        callq   *%r11

        addq    $0x38, %rsp
        ret
        .size   ms_call6, . - ms_call6

        .section .note.GNU-stack,"",@progbits
