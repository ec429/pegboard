/* LD script for pegboard binaries */
OUTPUT_FORMAT("binary")
OUTPUT_ARCH("z80")
MEMORY {
   initprog : ORIGIN = 0x0, LENGTH = 0x40
   program : ORIGIN = 0x40, LENGTH = 0x1bc0
   isr : ORIGIN = 0x1c00, LENGTH = 0x400 /* stores interrupt table and optionally other interrupt handling code */
   page1 : ORIGIN = 0x4000 LENGTH = 0x4000
   page2 : ORIGIN = 0x8000 LENGTH = 0x4000
   page3 : ORIGIN = 0xC000 LENGTH = 0x4000
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
.page1 : {
		*(.page1)
		*(page1)
		} > page1
.page2 : {
		*(.page2)
		*(page2)
		} > page2
.page3 : {
		*(.page3)
		*(page3)
		} > page3
}
