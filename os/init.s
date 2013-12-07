.section init, "rx"
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
	LD IY,0
	ADD IY,SP		; IY points to the percpu_struct
	PUSH DE
	JP main

.data
cpuindex_lock: .byte 0xfe
cpuindex: .byte 0

; struct percpu_struct {
;	u8 unused;
;   u8 cpuid;
; }
