/* LD script for multi80 binaries */
OUTPUT_FORMAT("binary")
OUTPUT_ARCH("z80")
MEMORY {
   program : ORIGIN = 0x0, LENGTH = 0x3c00
   isr : ORIGIN = 0x3c00, LENGTH = 0x400
}
SECTIONS
{
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
