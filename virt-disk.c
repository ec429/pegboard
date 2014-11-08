/*
	pegasus - emulator for pegboard, hypothetical SMP Z80 machine
	
	Copyright Edward Cree, 2010-14
	virt-disk - virtual disk device
*/
#include "virt-disk.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>
#include <errno.h>
#include "pegbus.h"

#define VIRT_DISK_ADDR_CMD	0x100
#define VIRT_DISK_CMD_GETSIZE	0x20
#define VIRT_DISK_CMD_SYNCCMD	0x30

struct virt_disk_dev
{
	int fd;
	bool shutup, paged, sync;
	uint16_t offset;
};

uint8_t virt_disk_write_trap(struct pegbus_device *self, uint16_t addr, uint8_t data)
{
	//fprintf(stderr, "virt_disk_write_trap slot %x addr %04x data %02x\n", self->slot, addr, data);
	struct virt_disk_dev *dev=self->dev;
	if(!dev)
		return(data);
	if(addr==PB_ADDR_CMD)
	{
		dev->shutup=(data==PB_CMD_SHUTUP);
	}
	else if(addr==VIRT_DISK_ADDR_CMD)
	{
		dev->offset=0;
		self->do_tick=data;
	}
	return(data);
}

#define pb_irq()	if(dev->sync) { dev->sync=false; } else if(!dev->shutup) { self->irq=true; }
#define complete()	do { pb_mem(VIRT_DISK_ADDR_CMD)|=0x80; self->do_tick=false; pb_irq(); } while(0)
#define error(_e)	do { pb_mem(VIRT_DISK_ADDR_CMD)=0xe0|(_e); self->do_tick=false; pb_irq(); } while(0)

void virt_disk_tick(struct pegbus_device *self)
{
	struct virt_disk_dev *dev=self->dev;
	if(!dev)
	{
		error(0);
		return;
	}
	uint8_t cmd=pb_mem(VIRT_DISK_ADDR_CMD);
	if(!cmd)
	{
		self->do_tick=false;
		return;
	}
	if(cmd==VIRT_DISK_CMD_GETSIZE)
	{
		pb_mem(VIRT_DISK_ADDR_CMD+1)=0xff; // max PL
		pb_mem(VIRT_DISK_ADDR_CMD+2)=0xff; // max PH
		pb_mem(VIRT_DISK_ADDR_CMD+3)=0x0f; // max SL
		complete();
		return;
	}
	if(cmd==VIRT_DISK_CMD_SYNCCMD)
	{
		pb_mem(VIRT_DISK_ADDR_CMD)|=0x80;
		dev->sync=true;
		self->do_tick=false;
		return;
	}
	uint8_t width=cmd&0xf;
	bool wr=cmd&0x10;
	uint8_t pl=pb_mem(VIRT_DISK_ADDR_CMD+1),
	        ph=pb_mem(VIRT_DISK_ADDR_CMD+2),
	        sl=pb_mem(VIRT_DISK_ADDR_CMD+3);
	if(!sl||sl>0xf)
	{
		error(1);
		return;
	}
	if(!dev->paged)
	{
		uint16_t page=(ph<<8)|pl;
		if(lseek(dev->fd, ((uint32_t)page)<<12, SEEK_SET)<0)
		{
			error(2);
			return;
		}
		dev->paged=true;
	}
	uint8_t *buf=self->raw[sl]+((dev->offset++)&0xfff);
	if(wr)
	{
		if(write(dev->fd, buf, 1)!=1)
		{
			error(3);
			return;
		}
	}
	else
	{
		int rc=read(dev->fd, buf, 1);
		if(rc<0)
		{
			error(4);
			return;
		}
		else if(!rc)
		{
			*buf=0;
		}
	}
	if(dev->offset>=(width<<12))
	{
		complete();
		dev->paged=false;
	}
}

int virt_disk_attach(int fd)
{
	if(fd<0)
		return(-EBADF);
	struct virt_disk_dev *dev=malloc(sizeof(*dev));
	if(!dev)
		return(-ENOMEM);
	dev->fd=fd;
	dev->shutup=false;
	dev->paged=false;
	dev->sync=false;
	return(pegbus_attach_device(VIRT_DISK_ID, 0x104, NULL, virt_disk_write_trap, virt_disk_tick, dev));
}

int virt_disk_destroy(int slot)
{
	struct pegbus_device *self=pbdevs+slot;
	if(self->config.device_id!=VIRT_DISK_ID) return(-EINVAL);
	struct virt_disk_dev *dev=self->dev;
	if(!dev)
		return(-EIO);
	int rc=fsync(dev->fd);
	if(rc) return(rc);
	free(dev);
	return(pegbus_destroy_device(self));
}
