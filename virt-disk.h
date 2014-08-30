#pragma once
/*
	pegasus - emulator for pegboard, hypothetical SMP Z80 machine
	
	Copyright Edward Cree, 2010-14
	virt-disk - virtual disk device
*/

#define VIRT_DISK_ID	0xfed0

int virt_disk_attach(int fd);
int virt_disk_destroy(int slot);
