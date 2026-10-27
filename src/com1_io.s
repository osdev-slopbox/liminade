/*  liminade x86 port I/O helpers for the COM1 debug UART.
 *
 *  GNAT 16.2.0 does not support inline assembly (pragma Asm reports
 *  "unrecognized pragma"), so the two instructions needed for serial
 *  output live here.  System V ABI: the port arrives in DI, the byte in SIL.
 */

        .section .text

        .globl  out8
        .type   out8, @function
out8:
        movw    %di, %dx
        movb    %sil, %al
        outb    %al, %dx
        ret
        .size   out8, . - out8

        .globl  in8
        .type   in8, @function
in8:
        movw    %di, %dx
        xorl    %eax, %eax
        inb     %dx, %al
        ret
        .size   in8, . - in8

        .section .note.GNU-stack,"",@progbits
