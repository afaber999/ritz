__memstart = 0x80000000;
__stack_top =__memstart + 0x2000;

CLINT_BASE_ADDR = 0x02000000;
CLINT_MTIMECMP_ADDR = CLINT_BASE_ADDR + 0x4000;
CLINT_MTIME_ADDR = CLINT_BASE_ADDR + 0xBFF8;
UART_BUF_REG_ADDR = 0x10000000;

ENTRY(_start)

SECTIONS
{
	. = __memstart;
	.text : ALIGN(16) {
		*(.text)
	}

	.data : ALIGN(16) {
		*(.rodata)
		*(.rodata.*)
		*(.data)
		*(.data.*)
	}

	.sdata : ALIGN(16) {
		__sdata_start = .;
		*(.sdata)
		*(.sdata.*)
		*(.sdata2)
		*(.sdata2.*)
		__sdata_end = .;
	}


	.sbss (NOLOAD) : ALIGN(16) {
		__sbss_start = .;
		__bss_start = .;
		*(.sbss)
		*(.sbss.*)
		*(.scommon)
		__sbss_end = .;
	}

	.bss : ALIGN( 16 ) {
		*(.bss)
		*(.bss.*)
		__bss_end = .;
		__BSS_END__ = .;
	}

	__global_pointer$ = __sdata_start + 0x800;
    
	_sstack = __stack_top; 
}

