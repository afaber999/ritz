.section .text
.globl _start

    .equ UART0_BASE,   0x10000000
    .equ UART_THR,     0x00
    .equ UART_LSR,     0x05
    .equ UART_LSR_THRE,0x20

    .equ CLINT_BASE,   0x02000000
    .equ CLINT_MSIP,   0x0000
    .equ MSIP_STRIDE,  4

_start:
    la      sp, _stack_top

    # mtvec -> trap handler
    la      t0, trap_handler
    csrw    mtvec, t0

    # Print boot message
    la      a0, msg_boot
    jal     ra, puts

    # Enable machine software interrupt (mie.MSIE, bit 3)
    li      t0, (1 << 3)
    csrs    mie, t0

    # Enable global machine interrupts (mstatus.MIE, bit 3)
    li      t0, (1 << 3)
    csrs    mstatus, t0

    la      a0, msg_trigger
    jal     ra, puts

    # Trigger MSI for current hart: msip[hartid] = 1
    csrr    t1, mhartid
    li      t2, MSIP_STRIDE
    mul     t1, t1, t2
    li      t3, (CLINT_BASE + CLINT_MSIP)
    add     t3, t3, t1
    li      t4, 1
    sw      t4, 0(t3)

wait_irq:
    la      t0, irq_seen
    lw      t1, 0(t0)
    bnez    t1, done
    wfi
    j       wait_irq

done:
    la      a0, msg_done
    jal     ra, puts

hang:
    wfi
    j       hang

# a0 = pointer to 0-terminated string
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

# a1 = char
putc:
1:
    li      t0, UART0_BASE
    lbu     t1, UART_LSR(t0)
    andi    t1, t1, UART_LSR_THRE
    beqz    t1, 1b
    sb      a1, UART_THR(t0)
    ret

trap_handler:
    csrr    t0, mcause

    # Interrupt bit set + cause 3 => machine software interrupt
    li      t1, 0x80000003
    bne     t0, t1, trap_other

    # Clear msip[hartid]
    csrr    t2, mhartid
    li      t3, MSIP_STRIDE
    mul     t2, t2, t3
    li      t4, (CLINT_BASE + CLINT_MSIP)
    add     t4, t4, t2
    sw      x0, 0(t4)

    # Mark seen
    la      t5, irq_seen
    li      t6, 1
    sw      t6, 0(t5)

    la      a0, msg_irq
    jal     ra, puts

    mret

trap_other:
    la      a0, msg_badtrap
    jal     ra, puts
    j       hang

    .section .rodata
msg_boot:    .asciz "Booting in M-mode\r\n"
msg_trigger: .asciz "Triggering machine software interrupt...\r\n"
msg_irq:     .asciz "In trap handler: MSIP interrupt received\r\n"
msg_done:    .asciz "Back in main: interrupt handled\r\n"
msg_badtrap: .asciz "Unexpected trap\r\n"

    .section .bss
    .align 4
irq_seen:    .word 0

    .section .stack, "aw", @nobits
    .align 12
stack_area:  .space 4096
_stack_top:
