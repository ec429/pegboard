.include "debug.inc"
.include "sched.inc"

PEGBUS_DRIVER_SLOTS	equ 8
PEGBUS_CMD_SHUTUP	equ 0xf0

.text

.globl pegbus_setup	; initialise pegbus handling
pegbus_setup:
	LD IX,pegbus_drivers
	CALL init_list_head
					; hook up the IRQ lines for all 16 possible pegbus slots
	LD HL,INT_pegbus_0
	LD DE,(INT_pegbus_1-INT_pegbus_0); makes use of the fact that they're all the same length
	LD (0x0f80),HL
	ADD HL,DE
	LD (0x0f82),HL
	ADD HL,DE
	LD (0x0f84),HL
	ADD HL,DE
	LD (0x0f86),HL
	ADD HL,DE
	LD (0x0f88),HL
	ADD HL,DE
	LD (0x0f8a),HL
	ADD HL,DE
	LD (0x0f8c),HL
	ADD HL,DE
	LD (0x0f8e),HL
	ADD HL,DE
	LD (0x0f90),HL
	ADD HL,DE
	LD (0x0f92),HL
	ADD HL,DE
	LD (0x0f94),HL
	ADD HL,DE
	LD (0x0f96),HL
	ADD HL,DE
	LD (0x0f98),HL
	ADD HL,DE
	LD (0x0f9a),HL
	ADD HL,DE
	LD (0x0f9c),HL
	ADD HL,DE
	LD (0x0f9e),HL
	RET

INT_pegbus_0:
	EX AF,AF'
	LD A,0
	JR INT_pegbus

INT_pegbus_1:
	EX AF,AF'
	LD A,1
	JR INT_pegbus

INT_pegbus_2:
	EX AF,AF'
	LD A,2
	JR INT_pegbus

INT_pegbus_3:
	EX AF,AF'
	LD A,3
	JR INT_pegbus

INT_pegbus_4:
	EX AF,AF'
	LD A,4
	JR INT_pegbus

INT_pegbus_5:
	EX AF,AF'
	LD A,5
	JR INT_pegbus

INT_pegbus_6:
	EX AF,AF'
	LD A,6
	JR INT_pegbus

INT_pegbus_7:
	EX AF,AF'
	LD A,7
	JR INT_pegbus

INT_pegbus_8:
	EX AF,AF'
	LD A,8
	JR INT_pegbus

INT_pegbus_9:
	EX AF,AF'
	LD A,9
	JR INT_pegbus

INT_pegbus_a:
	EX AF,AF'
	LD A,0xa
	JR INT_pegbus

INT_pegbus_b:
	EX AF,AF'
	LD A,0xb
	JR INT_pegbus

INT_pegbus_c:
	EX AF,AF'
	LD A,0xc
	JR INT_pegbus

INT_pegbus_d:
	EX AF,AF'
	LD A,0xd
	JR INT_pegbus

INT_pegbus_e:
	EX AF,AF'
	LD A,0xe
	JR INT_pegbus

INT_pegbus_f:
	EX AF,AF'
	LD A,0xf

INT_pegbus:
	EXX
	PUSH IX
.if DEBUG
	PUSH AF
	PERCPU
	LD IY,0xfffe
	EX DE,HL
	ADD IY,DE		; IY points to the percpu_struct
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,pegbus_irq_1
	CALL kputs_unlocked
	POP AF			; pegbus slot id
	PUSH AF
	CALL kprint_hex_unlocked
	LD HL,pegbus_irq_2
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	POP AF
.endif
	LD BC,0x0f04	; get page mapped in at 0xf000
	IN E,(C)
	LD D,A
	PUSH DE
	LD B,0x4f
	RLCA
	RLCA
	RLCA
	RLCA
	OUT (C),A		; map in device's first page at 0xf000
	LD IX,pegbus_devices; device = pegbus_devices+(slot*6)
	LD A,D
	RLCA
	ADD A,D
	RLCA
	LD B,0
	LD C,A
	ADD IX,BC
	CALL spin_lock
	LD L,(IX+4)
	LD H,(IX+5)
	LD A,L
	OR H
	JR NZ,INT_pegbus_call_driver
	LD HL,(0xf000)
	LD (IX+1),L
	LD (IX+2),H
	LD A,(0xf002)
	LD (IX+3),A
	PUSH IX
	LD IX,pegbus_drivers; find a matching driver (by device_id)
_INT_pegbus_next_driver:
	LD E,(IX+0)
	LD D,(IX+1)
	PUSH HL
	LD HL,pegbus_drivers; end of the list?
	AND A			; clear carry
	SBC HL,DE
	POP HL
	JR Z,_INT_pegbus_no_driver_found
	PUSH DE
	POP IX
	LD A,(IX+4)
	CP L
	JR NZ,_INT_pegbus_next_driver
	LD A,(IX+5)
	CP H
	JR NZ,_INT_pegbus_next_driver
	CALL _INT_pegbus_do_probe
	POP IX
	CALL spin_unlock
	JR _INT_pegbus_out
_INT_pegbus_no_driver_found:
	LD IX,0xf000	; send it a SHUTUP so we won't get any more interrupts
	LD (IX+3),PEGBUS_CMD_SHUTUP; if we register a matching driver later, it'll get probed then
	POP IX
	CALL spin_unlock
.if DEBUG
	PUSH HL
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,pegbus_no_driver
	CALL kputs_unlocked
	POP HL
	PUSH HL
	LD A,H
	CALL kprint_hex_unlocked
	POP HL
	LD A,L
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
.endif
_INT_pegbus_out:
	POP DE			; E=oldpage
	LD BC,0x0f04	; restore previously mapped page
	OUT (C),E
	POP IX
	EXX
	EX AF,AF'
	EI
	RETI
INT_pegbus_call_driver:
	CALL spin_unlock
	CALL panic

_INT_pegbus_do_probe:
	LD L,(IX+6)
	LD H,(IX+7)
	POP BC			; return address
	POP IX			; struct pegbus_device
	PUSH IX
	PUSH BC
	JP (HL)

.data
.if DEBUG
pegbus_irq_1: .asciz "pegbus device "
pegbus_irq_2: .asciz " interrupted CPU "
pegbus_no_driver: .asciz "No driver for pegbus device_id "
.endif
pegbus_devices:.rept 16
; struct pegbus_device {
;	spinlock_t lock;
;	uint16_t device_id;
;	uint8_t bus_version;
;	struct pegbus_driver *driver;
;}
.byte 0xfe,0,0,0,0,0
.endr

.bss
pegbus_drivers: .skip 4
pegbus_driver_slots: .skip PEGBUS_DRIVER_SLOTS*PEGBUS_DRIVER_SIZE
; struct pegbus_driver {
;	struct list_head list;
;	uint16_t device_id;
;	void (*probe)(struct pegbus_device *device);
;}
PEGBUS_DRIVER_SIZE	equ 8; sizeof(struct pegbus_driver)
