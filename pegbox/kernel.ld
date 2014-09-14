/* LD script for pegboard kernel */
OUTPUT_FORMAT("binary")
OUTPUT_ARCH("z80")
MEMORY {
   initprog : ORIGIN = 0x0, LENGTH = 0x80
   initdata : ORIGIN = 0x80, LENGTH = 0x80
   program : ORIGIN = 0x300, LENGTH = 0x1cc0
   drivers : ORIGIN = 0x1fc0, LENGTH = 0x40 /* pegbus driver registration */
   isr : ORIGIN = 0x101, LENGTH = 0xff /* interrupt service routine */
   ivt : ORIGIN = 0x200, LENGTH = 0x100 /* interrupt vector table */
}
SECTIONS
{
.init : {
		*(.init)
		*(init)
		} > initprog
.initd : {
		*(.initd)
		*(initd)
		} > initdata
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
.drv : {
		*(.drv)
		*(drv)
		} > drivers
}
