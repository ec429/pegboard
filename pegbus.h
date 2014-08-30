#pragma once
/*
	pegasus - emulator for pegboard, hypothetical SMP Z80 machine
	
	Copyright Edward Cree, 2010-14
	pegbus - peripheral device bus
*/
#include "types.h"
#include <stdbool.h>

#define IO_PEGBUS	0x80
#define PB_MAX_DEV	8 /* Number of pegbus slots on mmu */
struct pegbus_config
{
	uint16_t device_id; /* little-endian! */
	uint8_t bus_version;
	uint8_t command;
};

#define PB_ADDR_CMD		3
#define PB_CMD_SHUTUP	0xf0

struct pegbus_device; /* forward declaration */

typedef uint8_t (*pegbus_trap)(struct pegbus_device *self, uint16_t addr, uint8_t data);
typedef void (*pegbus_tick)(struct pegbus_device *self);

/* Access to device memory.  Can be used as lvalues */
#define pb_mem_paged(_page, _addr)	self->raw[(_page)][(_addr)]
#define pb_mem(_addr)	pb_mem_paged((_addr)>>12, (_addr)&0xfff)

struct pegbus_device
{
	bool attached;
	bool irq;
	bool do_tick;
	uint8_t slot; /* for emulator debugging only - real pegbus devices don't know their slot */
	uint16_t trap_addr; /* addresses below this trigger a trap */
	pegbus_trap read; /* given data that would be read, returns new data to read */
	pegbus_trap write; /* given data that were written, returns new data to write */
	pegbus_tick tick; /* executed every clock cycle as long as do_tick is set */
	void *dev; /* device-specific emulation data */
	union
	{
		ram_page raw[16];
		struct pegbus_config config;
	}; /* anonymous union */
};

extern struct pegbus_device pbdevs[PB_MAX_DEV];

/* Attach a device to the pegbus.  Returns slot number */
int pegbus_attach_device(uint16_t device_id, uint16_t trap_addr, pegbus_trap read, pegbus_trap write, pegbus_tick tick, void *dev);
/* Detach a device from the pegbus */
int pegbus_destroy_device(struct pegbus_device *self);

uint8_t pegbus_test_read_trap(struct pegbus_device *self, uint16_t addr, uint8_t data);
uint8_t pegbus_test_write_trap(struct pegbus_device *self, uint16_t addr, uint8_t data);
uint8_t pegbus_ro_write_trap(struct pegbus_device *self, uint16_t addr, uint8_t data); /* make trapped-addresses read-only */
