.text
  .equ CTX_RA, 0
  .equ CTX_SP, 4
  .equ CTX_GP, 8
  .equ CTX_TP, 12
  .equ CTX_T0, 16
  .equ CTX_T1, 20
  .equ CTX_T2, 24
  .equ CTX_S0, 28
  .equ CTX_S1, 32
  .equ CTX_A0, 36
  .equ CTX_A1, 40
  .equ CTX_A2, 44
  .equ CTX_A3, 48
  .equ CTX_A4, 52
  .equ CTX_A5, 56
  .equ CTX_A6, 60
  .equ CTX_A7, 64
  .equ CTX_S2, 68
  .equ CTX_S3, 72
  .equ CTX_S4, 76
  .equ CTX_S5, 80
  .equ CTX_S6, 84
  .equ CTX_S7, 88
  .equ CTX_S8, 92
  .equ CTX_S9, 96
  .equ CTX_S10, 100
  .equ CTX_S11, 104
  .equ CTX_T3, 108
  .equ CTX_T4, 112
  .equ CTX_T5, 116
  .equ CTX_T6, 120
  .equ CTX_MEPC, 124
  .equ CTX_SIZE, 128

  .global _start
  .type _start, @function
  .extern schedulerInit
  .extern handleTrap
  .extern current_task_ctx
  .extern UART_BUF_REG_ADDR

_start:

  # Initialize global pointer and initial stack.
.option push
.option norelax
  la gp, __global_pointer$
  la sp, _sstack
.option pop

  # Clear the bss segment.
  la a0, __bss_start
  la a1, __BSS_END__

clear_bss:
  bgeu a0, a1, done_bss
  sb x0, 0(a0)
  addi a0, a0, 1
  beq x0, x0, clear_bss

done_bss:
  call schedulerInit
  la t0, current_task_ctx
  lw t1, 0(t0)
  csrw mscratch, t1

  call main

  .global _task_exit
_task_exit:
  ebreak

.align 4
.global timervec

timervec:
  # Swap a0 with mscratch so a0 becomes the current task context pointer.
  csrrw a0, mscratch, a0

  # Save all integer registers plus mepc for the interrupted task.
  sw ra, CTX_RA(a0)
  sw sp, CTX_SP(a0)
  sw gp, CTX_GP(a0)
  sw tp, CTX_TP(a0)
  sw t0, CTX_T0(a0)
  sw t1, CTX_T1(a0)
  sw t2, CTX_T2(a0)
  sw s0, CTX_S0(a0)
  sw s1, CTX_S1(a0)
  sw a1, CTX_A1(a0)
  sw a2, CTX_A2(a0)
  sw a3, CTX_A3(a0)
  sw a4, CTX_A4(a0)
  sw a5, CTX_A5(a0)
  sw a6, CTX_A6(a0)
  sw a7, CTX_A7(a0)
  sw s2, CTX_S2(a0)
  sw s3, CTX_S3(a0)
  sw s4, CTX_S4(a0)
  sw s5, CTX_S5(a0)
  sw s6, CTX_S6(a0)
  sw s7, CTX_S7(a0)
  sw s8, CTX_S8(a0)
  sw s9, CTX_S9(a0)
  sw s10, CTX_S10(a0)
  sw s11, CTX_S11(a0)
  sw t3, CTX_T3(a0)
  sw t4, CTX_T4(a0)
  sw t5, CTX_T5(a0)
  sw t6, CTX_T6(a0)
  csrr t0, mscratch
  sw t0, CTX_A0(a0)
  csrr t0, mepc
  sw t0, CTX_MEPC(a0)

  csrr a1, mcause
  csrr a2, mtval
  call handleTrap

restore_context:
  csrw mscratch, a0

  lw t0, CTX_MEPC(a0)
  csrw mepc, t0

  lw ra, CTX_RA(a0)
  lw sp, CTX_SP(a0)
  lw gp, CTX_GP(a0)
  lw tp, CTX_TP(a0)
  lw t1, CTX_T1(a0)
  lw t2, CTX_T2(a0)
  lw s0, CTX_S0(a0)
  lw s1, CTX_S1(a0)
  lw a1, CTX_A1(a0)
  lw a2, CTX_A2(a0)
  lw a3, CTX_A3(a0)
  lw a4, CTX_A4(a0)
  lw a5, CTX_A5(a0)
  lw a6, CTX_A6(a0)
  lw a7, CTX_A7(a0)
  lw s2, CTX_S2(a0)
  lw s3, CTX_S3(a0)
  lw s4, CTX_S4(a0)
  lw s5, CTX_S5(a0)
  lw s6, CTX_S6(a0)
  lw s7, CTX_S7(a0)
  lw s8, CTX_S8(a0)
  lw s9, CTX_S9(a0)
  lw s10, CTX_S10(a0)
  lw s11, CTX_S11(a0)
  lw t3, CTX_T3(a0)
  lw t4, CTX_T4(a0)
  lw t5, CTX_T5(a0)
  lw t6, CTX_T6(a0)
  lw t0, CTX_T0(a0)
  lw a0, CTX_A0(a0)
  mret

.global startFirstTask
.type startFirstTask, @function
startFirstTask:
  # Make mret legal/effective outside trap entry: return to M-mode with interrupts enabled.
  li t2, 0x00001800      # mstatus.MPP mask
  csrrc x0, mstatus, t2  # clear MPP
  li t2, 0x00001880      # set MPP=3 (M-mode), MPIE=1
  csrrs x0, mstatus, t2

  la t0, current_task_ctx
  lw a0, 0(t0)
  j restore_context

.size startFirstTask, .-startFirstTask
  
.size _start, .-_start
