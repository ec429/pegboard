/* LD script for multi80 binaries */
OUTPUT_FORMAT("binary")
OUTPUT_ARCH("z80")
MEMORY {
   initprog : ORIGIN = 0x0, LENGTH = 0x40
   program : ORIGIN = 0x40, LENGTH = 0x5bc0
   isr : ORIGIN = 0x5c00, LENGTH = 0x400
}
SECTIONS
{
.init : {
		*(.init)
		*(init)
		} > initprog
.text : {
		*(.text)
		*(text)
		} > program
.isr : {
		*(.isr)
		*(isr)
		} > isr
.bss : {
		*(.bss)
		*(bss)
		} > program
.data : {
		*(.data)
		*(data)
		} > program
}
