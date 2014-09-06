; struct list_head { struct list_head *next, *prev };
; should be embedded in another struct
; examples:
;   empty list, head->next == head->prev == head
;   list of one element, head->next == head->prev == first; first->next == first->prev == head
;   list of two elements, head->next == second->prev == first; first->next == head->prev == second; second->next == first->prev == head
; heavily inspired by Linux's list.h

.text
.globl init_list_head; initialises *IX as an empty list_head
init_list_head:
	PUSH IX
	POP DE
	LD (IX+0),E		; head->next = head
	LD (IX+1),D
	LD (IX+2),E		; head->prev = head
	LD (IX+3),D
	RET

__list_add:			; insert a new entry HL between two known consecutive entries BC, DE
	PUSH HL
	POP IX
	LD (IX+0),E		; new->next = next
	LD (IX+1),D
	LD (IX+2),C		; new->prev = prev
	LD (IX+3),B
	PUSH BC
	POP IX
	LD (IX+0),L		; prev->next = new
	LD (IX+1),H
	PUSH DE
	POP IX
	LD (IX+2),L		; next->prev = new
	LD (IX+3),H
	RET

.globl list_add		; insert a new entry HL after the specified head BC
list_add:
	PUSH BC
	POP IX
	LD E,(IX+0)		; head->next
	LD D,(IX+1)
	JR __list_add

.globl list_add_tail; insert a new entry HL before the specified head DE
list_add_tail:
	PUSH DE
	POP IX
	LD C,(IX+0)		; head->prev
	LD B,(IX+1)
	JR __list_add

__list_del:			; delete the entry between BC and DE
	PUSH BC
	POP IX
	LD (IX+0),E		; prev->next = next
	LD (IX+1),D
	PUSH DE
	POP IX
	LD (IX+2),C		; next->prev = prev
	LD (IX+3),B
	RET

.globl list_del
list_del:			; delete entry HL from its list
	PUSH HL
	POP IX
	LD E,(IX+0)		; entry->next
	LD D,(IX+1)
	LD C,(IX+2)		; entry->prev
	LD B,(IX+3)
	LD (IX+0),0		; entry->next = NULL
	LD (IX+2),0		; entry->prev = NULL
	JR __list_del

.globl list_pop		; delete first entry from list IX, returning it in HL
list_pop:
	LD L,(IX+0)		; head->next
	LD H,(IX+1)
	PUSH IX
	POP BC			; head
	PUSH HL
	PUSH HL
	POP IX			; next
	LD E,(IX+0)		; next->next
	LD D,(IX+1)
	CALL __list_del
	POP HL			; next
	RET

.globl list_replace	; replace HL with DE.  Does not make HL empty!
list_replace:
	PUSH HL
	POP IX
	LD C,(IX+0)		; BC = old->next
	LD B,(IX+1)
	PUSH DE
	POP IX
	LD (IX+0),C		; new->next = BC
	LD (IX+1),B
	PUSH BC
	POP IX
	LD (IX+2),E		; new->next->prev = new
	LD (IX+3),D
	PUSH HL
	POP IX
	LD C,(IX+2)		; BC = old->prev
	LD B,(IX+3)
	PUSH DE
	POP IX
	LD (IX+2),C		; new->prev = BC
	LD (IX+3),B
	PUSH BC
	POP IX
	LD (IX+0),E		; new->prev->next = new
	LD (IX+1),D
	RET

.globl list_empty
list_empty:			; set Z flag if list at HL is empty
	PUSH HL
	POP IX
	JR __list_empty
.globl list_empty_ix; set Z flag if list at IX is empty
list_empty_ix:
	PUSH IX
	POP HL
__list_empty:
	LD A,L			; test head->next == head
	CP (IX+0)		; low byte
	RET NZ
	LD A,H			; high byte
	CP (IX+1)
	RET
