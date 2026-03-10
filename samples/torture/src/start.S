# ------------------------------------------------
# UART output (replace address if needed)
# ------------------------------------------------

.equ UART_TX, 0xf0000000

.text
.global _start
.type   _start, @function


# ------------------------------------------------
# ENTRY
# ------------------------------------------------
_start:
  # Initialize global pointer
.option push
.option norelax
  la		gp,__global_pointer$
  la    sp, __stack_top
.option pop


  la a0, banner
  jal ra, print_str

  jal ra, test_x0
  jal ra, test_branch
  jal ra, test_signext
  jal ra, test_jalr
  jal ra, test_memory
  jal ra, test_csr

  la a0, done
  jal ra, print_str

  ebreak


# ------------------------------------------------
# uart_putc(a0)
# ------------------------------------------------
uart_putc:
    li t0, UART_TX
    sb a0, 0(t0)
    ret


# ------------------------------------------------
# print_str(a0=pointer)
# preserves ABI
# ------------------------------------------------
print_str:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)

    mv s0, a0

1:
    lb a0, 0(s0)
    beqz a0, 2f
    jal ra, uart_putc
    addi s0, s0, 1
    j 1b

2:
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret


# ------------------------------------------------
# print_pass()
# ------------------------------------------------
print_pass:
    addi sp, sp, -16
    sw ra, 12(sp)

    la a0, passmsg
    jal ra, print_str

    lw ra, 12(sp)
    addi sp, sp, 16
    ret


# ------------------------------------------------
# print_fail()
# ------------------------------------------------
print_fail:
    addi sp, sp, -16
    sw ra, 12(sp)

    la a0, failmsg
    jal ra, print_str

    lw ra, 12(sp)
    addi sp, sp, 16
    ret



# ------------------------------------------------
# x0 immutability
# ------------------------------------------------
test_x0:

    addi sp, sp, -16
    sw ra, 12(sp)

    li x0, 5
    addi x0, x0, 10

    la a0, msg_x0
    jal ra, print_str

    bnez x0, fail_x0

    jal ra, print_pass
    j end_x0

fail_x0:
    jal ra, print_fail

end_x0:
    lw ra, 12(sp)
    addi sp, sp, 16
    ret


# ------------------------------------------------
# signed vs unsigned branch
# ------------------------------------------------
test_branch:

    addi sp, sp, -16
    sw ra, 12(sp)

    li t0, -1
    li t1, 1

    la a0, msg_branch
    jal ra, print_str

    blt t0, t1, 1f
    jal ra, print_fail
    j end_branch

1:
    bltu t0, t1, 2f
    jal ra, print_pass
    j end_branch

2:
    jal ra, print_fail

end_branch:
    lw ra, 12(sp)
    addi sp, sp, 16
    ret


# ------------------------------------------------
# sign extension
# ------------------------------------------------
test_signext:

    addi sp, sp, -32
    sw ra, 28(sp)

    la a0, msg_sign
    jal ra, print_str

    li t0, 0x80
    sb t0, 0(sp)

    lb t1, 0(sp)
    lbu t2, 0(sp)

    li t3, -128
    bne t1, t3, fail_sign

    li t3, 128
    bne t2, t3, fail_sign

    jal ra, print_pass
    j end_sign

fail_sign:
    jal ra, print_fail

end_sign:
    lw ra, 28(sp)
    addi sp, sp, 32
    ret


# ------------------------------------------------
# jalr masking
# ------------------------------------------------
test_jalr:

    addi sp, sp, -16
    sw ra, 12(sp)

    la a0, msg_jalr
    jal ra, print_str

    la t0, jalr_target
    addi t0, t0, 1

    jalr ra, t0, 0

    jal ra, print_fail
    j end_jalr

jalr_target:
    jal ra, print_pass

end_jalr:
    lw ra, 12(sp)
    addi sp, sp, 16
    ret


# ------------------------------------------------
# memory correctness
# ------------------------------------------------
test_memory:

    addi sp, sp, -32
    sw ra, 28(sp)

    la a0, msg_mem
    jal ra, print_str

    li t0, 0x12345678
    sw t0, 0(sp)

    lw t1, 0(sp)
    bne t0, t1, fail_mem

    jal ra, print_pass
    j end_mem

fail_mem:
    jal ra, print_fail

end_mem:
    lw ra, 28(sp)
    addi sp, sp, 32
    ret


# ------------------------------------------------
# CSR access
# ------------------------------------------------
test_csr:

    addi sp, sp, -16
    sw ra, 12(sp)

    la a0, msg_csr
    jal ra, print_str

    csrr t0, mhartid
    addi t0, t0, 0

    jal ra, print_pass

    lw ra, 12(sp)
    addi sp, sp, 16
    ret


# ------------------------------------------------
# DATA
# ------------------------------------------------

.section .rodata

banner:
.asciz "\nRISC-V emulator torture tests\n\n"

msg_x0:
.asciz "x0 register .... "

msg_branch:
.asciz "branch logic ... "

msg_sign:
.asciz "sign extension . "

msg_jalr:
.asciz "jalr mask ...... "

msg_mem:
.asciz "memory rw ...... "

msg_csr:
.asciz "csr access ..... "

passmsg:
.asciz "PASS\n"

failmsg:
.asciz "FAIL\n"

done:
.asciz "\nAll tests finished\n"