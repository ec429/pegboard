/* LD script for pegboard kernel */
OUTPUT_FORMAT("binary")
OUTPUT_ARCH("z80")
MEMORY {
   initprog : ORIGIN = 0x0, LENGTH = 0x42
   program : ORIGIN = 0x42, LENGTH = 0x1dcc
   isr : ORIGIN = 0x1e1e, LENGTH = 0xe2 /* interrupt service routine */
   ivt : ORIGIN = 0x1f00, LENGTH = 0x100 /* interrupt vector table */
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
.ivt : {
		*(.ivt)
		*(ivt)
		} > ivt
.bss : {
		*(.bss)
		*(bss)
		} > program
.data : {
		*(.data)
		*(data)
		} > program
}
