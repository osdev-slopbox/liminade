/*  liminade kernel handoff shims.
 *
 *  switch_page_tables
 *      Install the bootloader-built 4-level page tables and leave paging
 *      enabled.  The transition is done with paging temporarily disabled so
 *      that CR4.LA57 can be cleared safely even if the firmware booted with
 *      5-level paging; the low 4 GiB are identity mapped by the bootloader so
 *      the current instruction pointer and stack stay valid.
 *
 *  jump_to_kernel
 *      Set up the stack, clear interrupts and transfer control with a CALL so
 *      the callee sees the System V function-entry stack layout.
 *
 *  read_bsp_lapic_id
 *      CPUID leaf 1 EBX[31:24] (initial APIC ID) of the boot processor.
 */

        .section .text

        .globl  switch_page_tables
        .type   switch_page_tables, @function
switch_page_tables:
        cli
        movq    %rdi, %r8               /* new PML4 physical address */
        movq    %cr4, %rax
        testq   $0x1000, %rax           /* LA57 (5-level paging) active? */
        jz      .Lsp_load
        /*  Drop to 4-level paging: disable paging, clear CR4.LA57, reload
         *  CR3, then re-enable.  The low 4 GiB are identity mapped by the
         *  bootloader, so the code and stack stay valid with paging off.  */
        movq    %cr0, %r9
        btrq    $31, %r9
        movq    %r9, %cr0
        movq    %cr4, %rax
        btrq    $12, %rax
        movq    %rax, %cr4
.Lsp_load:
        movq    %r8, %cr3
        movq    %cr0, %rax
        btsq    $31, %rax
        movq    %rax, %cr0
        ret
        .size   switch_page_tables, . - switch_page_tables

        .globl  jump_to_kernel
        .type   jump_to_kernel, @function
jump_to_kernel:
        cli
        movq    %rsi, %rsp              /* kernel stack top, 16-byte aligned */
        xorl    %ebp, %ebp
        pushq   $2                      /* RFLAGS: interrupts off, DF clear */
        popfq
        callq   *%rdi                   /* callee sees rsp % 16 == 8 */
1:      cli
        hlt
        jmp     1b
        .size   jump_to_kernel, . - jump_to_kernel

        .globl  read_bsp_lapic_id
        .type   read_bsp_lapic_id, @function
read_bsp_lapic_id:
        pushq   %rbx
        movl    $1, %eax
        xorl    %ecx, %ecx
        cpuid
        movl    %ebx, %eax
        shrl    $24, %eax
        popq    %rbx
        ret
        .size   read_bsp_lapic_id, . - read_bsp_lapic_id

/*  Freestanding libc shims.
 *
 *  GNAT emits calls to memcpy/memset for array and record assignments; there
 *  is no C library in the image, so provide the handful of routines the
 *  compiler can reference.
 */

        .section .text

        .globl  memcpy
        .type   memcpy, @function
memcpy:
        movq    %rdi, %rax
        movq    %rdx, %rcx
        rep     movsb
        ret
        .size   memcpy, . - memcpy

        .globl  memset
        .type   memset, @function
memset:
        movq    %rdi, %r8
        movq    %rsi, %rax
        movq    %rdx, %rcx
        rep     stosb
        movq    %r8, %rax
        ret
        .size   memset, . - memset

        .globl  memmove
        .type   memmove, @function
memmove:
        movq    %rdi, %rax
        cmpq    %rsi, %rdi
        ja      .Lmemmove_back
        movq    %rdx, %rcx
        rep     movsb
        ret
.Lmemmove_back:
        testq   %rdx, %rdx
        je      .Lmemmove_done
        leaq    -1(%rdi,%rdx), %rdi
        leaq    -1(%rsi,%rdx), %rsi
        movq    %rdx, %rcx
        std
        rep     movsb
        cld
.Lmemmove_done:
        ret
        .size   memmove, . - memmove

        .globl  memcmp
        .type   memcmp, @function
memcmp:
        xorl    %eax, %eax
.Lmemcmp_loop:
        testq   %rdx, %rdx
        je      .Lmemcmp_done
        movzbl  (%rdi), %ecx
        movzbl  (%rsi), %r8d
        subl    %r8d, %ecx
        jne     .Lmemcmp_diff
        incq    %rdi
        incq    %rsi
        decq    %rdx
        jmp     .Lmemcmp_loop
.Lmemcmp_diff:
        movl    %ecx, %eax
.Lmemcmp_done:
        ret
        .size   memcmp, . - memcmp

        .section .note.GNU-stack,"",@progbits
