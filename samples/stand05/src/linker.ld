__stack_top = 0x8000;

ENTRY(_start)

SECTIONS
{
	. = 0x00000000;
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

