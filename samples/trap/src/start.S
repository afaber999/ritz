/* start.S - RV32 M-mode trap demo for QEMU virt */

    .section .text
    .globl _start

    .equ UART0_BASE,    0x10000000
    .equ UART_THR,      0
    .equ UART_LSR,      5
    .equ UART_LSR_THRE, 0x20

_start:
    la      sp, _stack_top

    /* Point mtvec at trap handler */
    la      t0, trap_handler
    csrw    mtvec, t0

    la      a0, msg_boot
    jal     ra, puts

    la      a0, msg_before
    jal     ra, puts

    /* Intentionally cause M-mode exception trap */
    ecall

    la      a0, msg_after
    jal     ra, puts

hang:
    wfi
    j       hang

/* trap handler for M-mode exceptions */
trap_handler:
    addi    sp, sp, -32
    sw      ra, 28(sp)
    sw      t0, 24(sp)
    sw      t1, 20(sp)
    sw      t2, 16(sp)
    sw      a0, 12(sp)
    sw      a1, 8(sp)
    sw      a2, 4(sp)

    csrr    t0, mcause
    li      t1, 11              /* ECALL from M-mode */
    bne     t0, t1, trap_unexpected

    la      a0, msg_in_handler
    jal     ra, puts

    /* Skip the trapping ecall instruction */
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    j       trap_exit

trap_unexpected:
    la      a0, msg_unexpected
    jal     ra, puts
1:
    j       1b

trap_exit:
    lw      a2, 4(sp)
    lw      a1, 8(sp)
    lw      a0, 12(sp)
    lw      t2, 16(sp)
    lw      t1, 20(sp)
    lw      t0, 24(sp)
    lw      ra, 28(sp)
    addi    sp, sp, 32
    mret

/* a0 = pointer to NUL-terminated string */
puts:
    addi    sp, sp, -16
    sw      ra, 12(sp)

puts_loop:
    lbu     t0, 0(a0)
    beqz    t0, puts_ret
    mv      a1, t0
    jal     ra, putc
    addi    a0, a0, 1
    j       puts_loop
puts_ret:
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

/* a1 = character */
putc:
2:
    li      t0, UART0_BASE
    lbu     t1, UART_LSR(t0)
    andi    t1, t1, UART_LSR_THRE
    beqz    t1, 2b
    sb      a1, UART_THR(t0)
    ret

    .section .rodata
msg_boot:        .asciz "RV32 M-mode trap demo\r\n"
msg_before:      .asciz "About to execute ECALL...\r\n"
msg_in_handler:  .asciz "Trap handler: ECALL from M-mode\r\n"
msg_after:       .asciz "Returned from trap via MRET\r\n"
msg_unexpected:  .asciz "Unexpected trap cause\r\n"

    .section .stack, "aw", @nobits
    .align 4
stack_area:      .space 2048
_stack_top: