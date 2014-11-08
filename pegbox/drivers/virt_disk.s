.include "pegbus.inc"

; driver for virt-disk (0xfed0)

PDEV_ID_VIRT_DISK equ 0xfed0

VIRT_DISK_DEVICE_SIZE equ 8; struct virt_disk_device {
VDSK_SIZL equ 0;	uint8_t size_l; /* PL returned by cmd 0x20; should always be 0xff */
VDSK_SIZH equ 1;	uint8_t size_h; /* PH returned by cmd 0x20 */
VDSK_FSIZ equ 2;	uint16_t full_size; /* (size_h + 1) * (size_l + 1) - 1, which == (size_h<<8)|size_l if size_l==0xff */
VDSK_MXSL equ 4;	uint8_t max_slot; /* SL returned by cmd 0x20 */
VDSK_ACSL equ 5;	uint8_t active_slot; /* slot currently being worked on or 0xff */
VDSK_ACPG equ 6;	uint16_t active_page; /* ph and pl for operation on active_slot */
;}

VDREG_BASE equ 0xf100
VDRO_CMD equ 0
VDRO_PL  equ 1
VDRO_PH  equ 2
VDRO_SL  equ 3
VDCMD_GETSIZE equ 0x20
VDCMD_SYNCCMD equ 0x30

.text
virt_disk_probe:; probe device *IX, mapped at 0xf000
	PUSH IX
	LD BC,VIRT_DISK_DEVICE_SIZE
	CALL kmalloc
	LD A,L
	OR H
	JR NZ,_virt_disk_probe_got_memory
	LD A,PEGBUS_CMD_SHUTUP
	LD (0xf003),A
	LD HL,STR_kmalloc
	CALL perror
_virt_disk_probe_failed:
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,virt_disk_probe_fail
	CALL kputs_unlocked
	POP IX
	LD A,(IX+PDEV_SLOT)
	CALL kprint_half_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	LD IX,kprint_lock
	CALL spin_unlock
	RET
_virt_disk_probe_got_memory:
	PUSH HL
	POP IX
	LD A,VDCMD_GETSIZE
	CALL virt_disk_cmd_sync
	LD (IX+VDSK_SIZL),L
	LD (IX+VDSK_SIZH),H
	INC L			; assert(size_l == 0xff)
	CALL NZ,panic
	DEC L
	LD (IX+VDSK_FSIZ),L
	LD (IX+VDSK_FSIZ+1),H
	LD (IX+VDSK_MXSL),D
	LD (IX+VDSK_ACSL),0xff
	PUSH IX
	POP HL
	POP IX
	PUSH IX
	LD (IX+PDEV_DATA),L
	LD (IX+PDEV_DATA+1),H
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,virt_disk_probed
	CALL kputs_unlocked
	POP IX
	LD A,(IX+PDEV_SLOT)
	CALL kprint_half_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	LD IX,kprint_lock
	CALL spin_unlock
	RET

; Run a command and spin for completion.  Should only be used for fast commands (e.g. 0x20)
virt_disk_cmd_sync:	; cmd in A, PH/PL in HL, SL in D.  Corresponding values at return.  Device mapped at 0xf000, and device->lock held
	PUSH IX
	PUSH AF
	LD IX,VDREG_BASE
	LD (IX+VDRO_CMD),VDCMD_SYNCCMD
_vdcs_sync_poll:
	LD C,(IX+VDRO_CMD)
	LD A,0x80
	AND C
	JR Z,_vdcs_sync_poll
	POP AF
	LD (IX+VDRO_PL),L
	LD (IX+VDRO_PH),H
	LD (IX+VDRO_SL),D
	LD (IX+VDRO_CMD),A
_vdcs_poll:
	LD C,(IX+VDRO_CMD)
	LD A,0x80
	AND C
	JR Z,_vdcs_poll
	LD A,0xf0
	AND C
	CP 0xe0
	JR NZ,_vdcs_ok
	SCF				; cmd Ex => error, so set carry
_vdcs_ok:
	LD L,(IX+VDRO_PL)
	LD H,(IX+VDRO_PH)
	LD D,(IX+VDRO_SL)
	LD A,C
	POP IX
	RET

.data
virt_disk_probed: .asciz "virt_disk: Probed disk (id 0xfed0) in slot "
virt_disk_driver: DECLARE_PEGBUS_DRIVER PDEV_ID_VIRT_DISK, virt_disk_probe
STR_kmalloc: .asciz "kmalloc"
virt_disk_probe_fail: .asciz "virt_disk: failed to probe device in slot "

.section drv
.word virt_disk_driver
