.text

.globl main			; per-CPU OS entry point.  Does not return
main:
	LD A,1
	OUT (0x05),A	; set pi 1 to page 1
	LD A,(IY+0)
	AND A
	CALL Z,cpu0_setup
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,start_msg_1
	CALL kputs_unlocked
	LD A,(IY+0)
	CALL kprint_hex_unlocked
	LD HL,start_msg_2
	CALL kputs_unlocked
	LD IX,kprint_lock
	CALL spin_unlock
; paging test: get a page, sleep a bit, and free it
	CALL get_page
	AND A
	JR NZ,now_free_it
	LD HL,STR_get_page
	CALL perror
	JR ptest_over
now_free_it:
	DJNZ .
	DJNZ .
	DJNZ .
	CALL free_page
	LD A,E
	AND A
	JR Z,ptest_over
	LD HL,STR_free_page
	CALL perror
ptest_over:
	HALT

cpu0_setup:
	CALL setup_mem_map
	LD HL,can_start_other_cpus
	LD (HL),1
	RET

.data
STR_get_page: .asciz "get_page"
STR_free_page: .asciz "free_page"
start_msg_1: .asciz "CPU #"
start_msg_2: .ascii " online"
.byte 0x0a,0
