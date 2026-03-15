  .text
  .global _start
  .type   _start, @function

_start:

  # Initialize global pointer
.option push
.option norelax
	la		gp,__global_pointer$
	la		sp,_sstack  
.option pop

    # Clear the bss segment
    la      a0,__bss_start      # a0 = start zeroing memory here
    la      a1,__BSS_END__      # a1 = end zeroing here-1

clear_bss:
    bgeu    a0,a1,done_bss      # while (!(a0 >= a1))
    sb      x0,0(a0)            #   *a0 = 0;
    addi    a0,a0,1             #   ++a0
    beq     x0,x0,clear_bss
done_bss:

    # call zig
    call    main

	  # abort execution here
    ebreak

.align 4
.global timervec
.global timervec_test
.extern CLINT_MTIMECMP_ADDR
.extern CLINT_MTIME_ADDR
.extern UART_BUF_REG_ADDR

timervec:
  csrrw a0, mscratch, a0

timervec_body:
  la x10, _save_area
  sw a1, 0(x10)
  sw a2, 4(x10)
  sw t0, 8(x10)
  sw t1, 12(x10)
  sw t2, 16(x10)
  sw t3, 20(x10)

  # Debug cause check: '@' for machine timer interrupt, '!' otherwise.
  csrr t3, mcause
  li t2, 0x80000007
  bne t3, t2, trap_not_timer

  # Re-arm timer interrupt on QEMU virt using CLINT MMIO.
  la t3, CLINT_MTIME_ADDR
  lw t0, 0(t3)
  lw t1, 4(t3)
  li t2, 20000000   # about two seconds, assume 10MHz clock mtime
  add t0, t0, t2
  sltu t2, t0, t2
  add t1, t1, t2

  la t3, CLINT_MTIMECMP_ADDR
  li a1, -1
  sw a1, 4(t3)
  sw t0, 0(t3)
  sw t1, 4(t3)

  la a0, UART_BUF_REG_ADDR
  addi a1, x0, '@'
  sw a1, 0(a0)
  j trap_done_marker

trap_not_timer:
  la a0, UART_BUF_REG_ADDR
  addi a1, x0, '!'
  sw a1, 0(a0)

trap_done_marker:
  la a0, _save_area
  lw a1, 0(a0)
  lw a2, 4(a0)
  lw t0, 8(a0)
  lw t1, 12(a0)
  lw t2, 16(a0)
  lw t3, 20(a0)

  csrrw a0, mscratch, a0
  mret

timervec_test:
  la a0, _save_area
  sw a1, 0(a0)
  sw a2, 4(a0)

  la a0, UART_BUF_REG_ADDR
  addi a1, x0, '@'
  sw a1, 0(a0)
  sw a1, 0(a0)
  sw a1, 0(a0)
  sw a1, 0(a0)
  sw a1, 0(a0)
  sw a1, 0(a0)

  lw a1, 0(a0)
  lw a2, 4(a0)
  ret


.size  _start, .-_start

_save_area:
  .space 128