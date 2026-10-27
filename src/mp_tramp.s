/*  Application-processor startup trampoline.
 *
 *  The bootstrap processor copies the block [mp_tramp_start, mp_tramp_end)
 *  into a 4 KiB page below 1 MiB (0x8000) and covers a 16-bit real-mode entry
 *  there, so that a SIPI with vector 0x08 lands on `mp_tramp_start`.
 *
 *  Everything below is position dependent: every absolute reference is
 *  expressed relative to `mp_tramp_start` (or is RIP-relative), and the code
 *  is run at exactly `MP.Trampoline_Address` (0x8000), which the 16-bit phase
 *  assumes when it loads DS/ES with the segment that maps that page.
 *
 *  The processor that arrives here:
 *    1. enters protected mode and then long mode with the bootloader's PML4,
 *    2. loads the machine state required by the Limine protocol,
 *    3. initialises its local APIC (xAPIC, SVR = 0x1FF, LVTs masked),
 *    4. publishes `mp_tramp_ack` so the BSP knows it is parked,
 *    5. spins on `mp_info->goto_address`, calling it with RDI = &mp_info when
 *       the executable publishes an entry point.
 *
 *  Patch fields (filled in by src/mp.adb before each SIPI):
 *    mp_tramp_cr3    - physical address of the shared PML4
 *    mp_tramp_lapic  - local APIC MMIO base
 *    mp_tramp_stack  - 64 KiB stack top for this processor
 *    mp_tramp_mpinfo - physical address of this processor's limine_mp_info
 */

        .section .text

        .globl  mp_tramp_start
mp_tramp_start:
        .code16
        cli
        movw    $0x0800, %ax            /* SIPI: CS = vector << 8 */
        movw    %ax, %ds
        movw    %ax, %es
        lgdt    (mp_tramp_gdt_ptr - mp_tramp_start)
        movl    %cr0, %eax
        orl     $0x00000001, %eax       /* CR0.PE */
        movl    %eax, %cr0
        /*  The flat descriptors have base 0, so the target offset is the
         *  linear address of the copied block plus the label offset.  */
        .byte   0xEA                    /* ljmp $0x18,$mp_tramp_pm32 */
        .word   0x8000 + (mp_tramp_pm32 - mp_tramp_start)
        .word   0x18

        .code32
mp_tramp_pm32:
        movw    $0x20, %ax              /* 32-bit flat data */
        movw    %ax, %ds
        movw    %ax, %es
        movw    %ax, %ss
        movw    %ax, %fs
        movw    %ax, %gs
        movl    $(0x8000 + (mp_tramp_cr3 - mp_tramp_start)), %eax
        movl    (%eax), %eax
        movl    %eax, %cr3
        movl    $0xC0000080, %ecx       /* IA32_EFER */
        rdmsr
        orl     $0x00000901, %eax       /* SCE | LME | NXE */
        wrmsr
        movl    %cr4, %eax
        orl     $0x000006A0, %eax       /* PAE | PGE | OSFXSR | OSXMMEXCPT */
        movl    %eax, %cr4
        movl    $0x80010011, %eax       /* PG | WP | ET | PE */
        movl    %eax, %cr0
        .byte   0xEA                    /* ljmp $0x28,$mp_tramp_lm64 */
        .long   0x8000 + (mp_tramp_lm64 - mp_tramp_start)
        .word   0x28

        .code64
mp_tramp_lm64:
        movq    mp_tramp_stack(%rip), %rsp
        movq    mp_tramp_mpinfo(%rip), %rbx
        xorl    %ebp, %ebp
        pushq   $2                      /* RFLAGS: IF = 0, DF = 0 */
        popfq
        /*  Force xAPIC mode (firmware may have left x2APIC enabled), then
         *  enable the local APIC and mask every LVT.  */
        movl    $0x1B, %ecx             /* IA32_APIC_BASE */
        rdmsr
        andl    $0xFFFFFBFF, %eax       /* clear EXTD (bit 10) */
        orl     $0x00000800, %eax       /* set EN (bit 11) */
        wrmsr
        movl    mp_tramp_lapic(%rip), %edi
        movl    $0x000001FF, 0x0F0(%rdi) /* SVR: enabled, vector 0xFF */
        movl    $0, 0x080(%rdi)          /* TPR */
        movl    $0x00010000, 0x320(%rdi) /* LVT timer */
        movl    $0x00010000, 0x330(%rdi) /* LVT thermal */
        movl    $0x00010000, 0x340(%rdi) /* LVT perf */
        movl    $0x00010000, 0x350(%rdi) /* LVT LINT0 */
        movl    $0x00010000, 0x360(%rdi) /* LVT LINT1 */
        movl    $0x00010000, 0x370(%rdi) /* LVT error */
        movl    $0x4D504B31, mp_tramp_ack(%rip) /* "MPK1": parked */

mp_tramp_park:
        movq    16(%rbx), %rax          /* mp_info->goto_address */
        testq   %rax, %rax
        jne     mp_tramp_release
        pause
        jmp     mp_tramp_park

mp_tramp_release:
        movq    %rbx, %rdi
        callq   *%rax
        movq    $0, 16(%rbx)            /* callee may return: re-park */
        jmp     mp_tramp_park

        .balign 8
.globl  mp_tramp_cr3
mp_tramp_cr3:
        .long   0
.globl  mp_tramp_lapic
mp_tramp_lapic:
        .long   0xFEE00000
        .balign 8
.globl  mp_tramp_stack
mp_tramp_stack:
        .quad   0
.globl  mp_tramp_mpinfo
mp_tramp_mpinfo:
        .quad   0
.globl  mp_tramp_ack
mp_tramp_ack:
        .long   0
        .balign 16
/*  Same layout as the BSP's GDT (see src/jump.s): null, 16-bit code/data,
 *  32-bit code/data, 64-bit code/data.  Selectors used here: 0x18 and 0x20
 *  for the 32-bit phase, 0x28 and 0x30 for long mode.  */
mp_tramp_gdt:
        .quad   0x0000000000000000
        .quad   0x00009A000000FFFF
        .quad   0x000093000000FFFF
        .quad   0x00CF9A000000FFFF
        .quad   0x00CF92000000FFFF
        .quad   0x00AF9A000000FFFF
        .quad   0x00CF92000000FFFF
mp_tramp_gdt_ptr:
        .word   55
        .long   0x8000 + (mp_tramp_gdt - mp_tramp_start)
        .balign 16
.globl  mp_tramp_end
mp_tramp_end:

        .section .note.GNU-stack,"",@progbits
