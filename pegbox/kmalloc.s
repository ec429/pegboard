.include "mem.inc"
.include "list.inc"
.include "errno.inc"
.include "debug.inc"
.include "spinlock.inc"

KMALLOC_FREL equ KMALLOC_BASE+LIST_HEAD_SIZE
KMALLOC_ZERO equ KMALLOC_FREL+LIST_HEAD_SIZE; all kmalloc(0) return this, and it can be free()d repeatedly.  The byte at this address is safe to scribble on (but don't do so on purpose)
KMALLOC_LOCK equ KMALLOC_ZERO+1
KMALLOC_FIRST equ KMALLOC_LOCK+1

HEAP_ITEM_SIZE equ 6
; struct heap_item {
KMHI_LIST equ 0;	struct list_head list;
KMHI_LEN  equ LIST_HEAD_SIZE;	uint16_t length;
KMHI_DATA equ LIST_HEAD_SIZE+2;	char data[];
;}

FREE_ITEM_SIZE equ 10
;struct free_item {
KMFI_LIST equ KMHI_LIST;	struct list_head list;
KMFI_LEN  equ KMHI_LEN ;	uint16_t length;
KMFI_FREL equ KMHI_DATA;	struct list_head frel;
;}

KMALLOC_INITIAL_FREE_BLOCK_LENGTH equ KMALLOC_PAGES*PAGE_SIZE-(KMALLOC_FIRST-KMALLOC_BASE)-HEAP_ITEM_SIZE

.globl init_kmalloc_arena; initialise the kmalloc arena
init_kmalloc_arena:
	BUILD_BUG_ON(KMALLOC_PAGES!=1)
	LD (IY+1),1		; mark our running process as init, so we can get_page
	CALL get_page
	LD (IY+1),0		; clear our running process (as we're not actually running init)
	AND A
	CALL Z,panic
	LD (kmalloc_ppage0),A
	LD BC,(KMALLOC_VPAGE0<<8)+4
	OUT (C),A		; page in phys A at virt KMALLOC_VPAGE0
	LD IX,KMALLOC_BASE; initialise kmalloc_base and kmalloc_frel
	CALL init_list_head
	PUSH IX
	LD IX,KMALLOC_LOCK
	LD (IX+0),SPINLOCK_UNLOCKED
	LD IX,KMALLOC_FREL
	CALL init_list_head
	LD IX,KMALLOC_FIRST; kmalloc_first->length = (arena_size - sizeof(*kmalloc_base) - sizeof(*kmalloc_frel) - sizeof(struct heap_item)) | 0x8000;
	LD HL,KMALLOC_INITIAL_FREE_BLOCK_LENGTH|0x8000
	LD (IX+KMFI_LEN),L
	LD (IX+KMFI_LEN+1),H
	PUSH IX
	POP HL
	POP BC
	CALL list_add	; list_add(&kmalloc_first->list, kmalloc_base);
	LD BC,KMALLOC_FREL
	LD HL,KMALLOC_FIRST+KMFI_FREL
	CALL list_add	; list_add(&kmalloc_first->frel, kmalloc_frel);
.if DEBUG
	LD HL,kmalloc_ready
	CALL kputs
.endif
	RET

.globl kmalloc		; allocate BC bytes, return in HL
kmalloc:
	LD A,0x80		; if (len & 0x8000) { errno = EINVAL; return NULL; }
	AND B
	LD E,EINVAL
	JR NZ,_kmalloc_fail
	LD A,B
	AND A
	JR NZ,_kmalloc_sizeok
	LD A,C
	AND A			; if (!len)
	JR NZ,_kmalloc_minsize
	LD HL,KMALLOC_ZERO;	return kmalloc_zero;
	RET
_kmalloc_minsize:
	CP LIST_HEAD_SIZE; else if (len < sizeof(struct list_head))
	JR NC,_kmalloc_sizeok
	LD C,LIST_HEAD_SIZE;	len = sizeof(struct list_head);
_kmalloc_sizeok:
	LD IX,KMALLOC_LOCK
	CALL spin_lock_irqsave
	LD IX,KMALLOC_FREL; struct list_head *ptr = frel;
_kmalloc_loop:		; while ((ptr = ptr->next) != frel) {
	PUSH IX
	LD L,(IX+KMFI_LIST)
	LD H,(IX+KMFI_LIST+1)
	POP DE
	PUSH HL
	AND A			; clear carry flag
	SBC HL,DE
	POP IX			; ptr = IX; item = container_of(ptr, struct free_item, frel); /* &item->frel == ptr */
	LD E,ENOMEM
	JR Z,_kmalloc_fail
	LD E,(IX-KMFI_FREL+KMFI_LEN); if (item->length < (len|0x8000))
	LD D,(IX-KMFI_FREL+KMFI_LEN+1)
	LD A,0x80
	OR B
	LD H,A
	LD L,C
	SBC HL,DE
	JR C,_kmalloc_loop;	continue;
	LD A,0x7f		; item->length &= ~0x8000;
	AND D
	LD D,A
	LD (IX-KMFI_FREL+KMFI_LEN+1),D
	PUSH BC			; if (item->length <= len + sizeof(struct free_item))
	PUSH DE
	LD HL,FREE_ITEM_SIZE+1
	ADD HL,BC
	SBC HL,DE
	POP DE
	POP BC
	JR C,_kmalloc_split
	PUSH IX
	PUSH IX
	POP HL
	CALL list_del	; list_del(&item->frel);
	BUILD_BUG_ON(KMFI_FREL != KMHI_DATA)
	POP HL			; ((struct heap_item *)item)->data
	LD E,0			; Successfully allocated!
	RET
_kmalloc_fail:
	LD IX,KMALLOC_LOCK
	CALL spin_unlock_irqsave
	LD HL,0
	RET
_kmalloc_split:
	LD HL,HEAP_ITEM_SIZE|0x8000; new_length = (item->length - len - sizeof(struct heap_item))|0x8000;
	ADD HL,BC
	EX DE,HL		; HL is now item->length
	AND A			; clear carry flag
	SBC HL,DE
	EX DE,HL		; DE is now new->length
	LD (IX-KMFI_FREL+KMFI_LEN),C; item->length = len;
	LD (IX-KMFI_FREL+KMFI_LEN+1),B
	PUSH IX
	BUILD_BUG_ON(KMFI_FREL != KMHI_DATA)
	ADD IX,BC		; struct free_item *new = (struct free_item *)(hi->data + len); /* == ((void *)item->frel) + len */
	LD (IX+KMFI_LEN),E; new->length = new_length
	LD (IX+KMFI_LEN+1),D
	POP BC			; list_add(&new->list, &item->list);
	PUSH BC
	BUILD_BUG_ON(KMFI_FREL != 6)
	DEC BC
	DEC BC
	DEC BC
	DEC BC
	DEC BC
	DEC BC
	PUSH IX
	PUSH IX
	POP HL
	BUILD_BUG_ON(KMHI_LIST != 0)
	BUILD_BUG_ON(KMFI_LIST != 0)
	CALL list_add
					; list_replace(&item->frel, &new->frel);
	POP HL			; is new
	POP DE			; is item->frel
	PUSH DE
	BUILD_BUG_ON(KMFI_FREL != 6)
	INC HL
	INC HL
	INC HL
	INC HL
	INC HL
	INC HL
	CALL list_replace
	LD E,0			; Successfully allocated!
	POP HL			; return ((struct heap_item *)item)->data; /* == item->frel */
	RET

.globl kfree		; free kmalloc'd memory at HL
kfree:
	CALL panic
	RET

.data
.if DEBUG
kmalloc_ready: .ascii "kmalloc arena ready, 0x"
.byte KMALLOC_PAGES+'0'-1
BUILD_BUG_ON(KMALLOC_INITIAL_FREE_BLOCK_LENGTH&0xfff != 0xff0)
.ascii "ff0 bytes"
.byte 0x0a, 0
.endif

.bss
kmalloc_ppage0: .byte 0
