.include "block.inc"

.include "debug.inc"
.include "spinlock.inc"
.include "pegbus.inc"

.text
.globl block_device_register; registers (struct block_device *)IX
block_device_register:
	BUILD_BUG_ON(BDEV_LIST != 0)
	PUSH IX
	PUSH IX
	POP HL
	LD DE,block_device_list
	CALL list_add_tail
	LD BC,4
	CALL kmalloc
	LD A,L
	OR H
	JR NZ,_bdr_got_memory
	LD HL,STR_kmalloc
	CALL perror
	RET
_bdr_got_memory:
	POP IX
	CALL block_device_name
	PUSH HL
	LD IX,kprint_lock
	CALL spin_lock	; safe without _irqsave because this function is always called with interrupts disabled (either because another spinlock is held, or because we're in an interrupt already)
	LD HL,bd_created
	CALL kputs_unlocked
	POP HL
	PUSH HL
	CALL kputs_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	POP HL
	CALL kfree
	RET

.globl block_device_name; writes name of (struct block_device *)IX to (char [4])HL
block_device_name:
	PUSH HL
	LD (HL),'p'
	INC HL
	LD (HL),'d'
	INC HL
	LD E,(IX+BDEV_DEV)
	LD D,(IX+BDEV_DEV+1)
	PUSH IX
	PUSH DE
	POP IX
	LD A,(IX+PDEV_SLOT)
	ADD A,'a'
	LD (HL),A
	INC HL
	LD (HL),0
	POP IX
	POP HL
	RET

.data
block_device_list: .word block_device_list, block_device_list
STR_kmalloc: .asciz "kmalloc"
bd_created: .asciz "Created block device "
