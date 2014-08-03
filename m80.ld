/* LD script for pegboard kernel */
OUTPUT_FORMAT("binary")
OUTPUT_ARCH("z80")
MEMORY {
   initprog : ORIGIN = 0x0, LENGTH = 0x42
   program : ORIGIN = 0x42, LENGTH = 0xdcc
   isr : ORIGIN = 0xe0e, LENGTH = 0xf2 /* interrupt service routine */
   ivt : ORIGIN = 0xf00, LENGTH = 0x100 /* interrupt vector table */
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
