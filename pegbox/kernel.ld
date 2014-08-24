/* LD script for pegboard kernel */
OUTPUT_FORMAT("binary")
OUTPUT_ARCH("z80")
MEMORY {
   initprog : ORIGIN = 0x0, LENGTH = 0x101
   program : ORIGIN = 0x300, LENGTH = 0x1d00
   isr : ORIGIN = 0x101, LENGTH = 0xff /* interrupt service routine */
   ivt : ORIGIN = 0x200, LENGTH = 0x100 /* interrupt vector table */
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
