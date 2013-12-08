.section init, "rx"
	DI
	LD D,0
	LD HL,cpuindex
	LD IX,cpuindex_lock
	CALL spin_lock
	LD E,(HL)
	INC (HL)
					; set up individual stack at 0xfffe - cpuindex*0x100
	LD A,0xff
	SUB E
	LD H,A
	LD L,0xfe
	LD SP,HL
	CALL spin_unlock
	LD IY,0xfffe
	ADD IY,SP		; IY points to the percpu_struct
	PUSH DE
	LD A,E
	AND A
	JR Z,start_main
	LD HL,can_start_other_cpus
wait_to_start:
	DJNZ .
	LD A,(HL)
	AND A
	JR Z,wait_to_start
start_main:
	JP main

.data
cpuindex_lock: .byte 0xfe
cpuindex: .byte 0
.globl can_start_other_cpus
can_start_other_cpus: .byte 0

; struct percpu_struct {
;   u8 cpuid;
;	u8 unused;
; }
