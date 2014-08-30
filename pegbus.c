#include "pegbus.h"
#include <errno.h>
#include <stdio.h>

struct pegbus_device pbdevs[PB_MAX_DEV];

int pegbus_attach_device(uint16_t device_id, uint16_t trap_addr, pegbus_trap read, pegbus_trap write, pegbus_tick tick, void *dev)
{
	unsigned int slot;
	for(slot=0;slot<PB_MAX_DEV;slot++)
		if(!pbdevs[slot].attached) break;
	if(slot==PB_MAX_DEV)
		return(-ENOENT);
	pbdevs[slot].attached=true;
	pbdevs[slot].irq=true; /* device needs to announce itself */
	pbdevs[slot].do_tick=false;
	pbdevs[slot].slot=slot;
	pbdevs[slot].trap_addr=trap_addr;
	pbdevs[slot].read=read;
	pbdevs[slot].write=write;
	pbdevs[slot].tick=tick;
	pbdevs[slot].dev=dev;
	pbdevs[slot].config=(struct pegbus_config){.device_id=device_id,.bus_version=0};
	pbdevs[slot].raw[0][sizeof(struct pegbus_config)]=0xff; /* end_of_caps */
	return(slot);
}

int pegbus_destroy_device(struct pegbus_device *self)
{
	if(!self->attached) return(-ENODEV);
	self->attached=false;
	self->do_tick=false;
	self->irq=false;
	self->dev=NULL;
	return(0);
}

uint8_t pegbus_test_read_trap(struct pegbus_device *self, uint16_t addr, uint8_t data)
{
	fprintf(stderr, "pegbus_test_read_trap slot %x addr %04x data %02x\n", self->slot, addr, data);
	return(data);
}

uint8_t pegbus_test_write_trap(struct pegbus_device *self, uint16_t addr, uint8_t data)
{
	fprintf(stderr, "pegbus_test_write_trap slot %x addr %04x data %02x\n", self->slot, addr, data);
	if(addr==3) // command register
		return(data);
	else if(addr<5)
		return pegbus_ro_write_trap(self, addr, data);
	return(data);
}

uint8_t pegbus_ro_write_trap(struct pegbus_device *self, uint16_t addr, __attribute__((unused)) uint8_t data)
{
	return(self->raw[addr>>12][addr&0xfff]);
}
