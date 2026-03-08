ENTRY(_start)
SECTIONS
{
	. = 0x00000000;
	/*. = 0xf0000000;*/
    .text : { _start = .; *(.text) }
    .data : { *(.data) }
}
