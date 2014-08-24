/*
	pegasus - emulator for pegboard, hypothetical SMP Z80 machine
	Uses z80 core from Spiffy <https://github.com/ec429/spiffy>
	
	Copyright Edward Cree, 2010-14
	License: GNU GPL v3+
*/

#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include "bits.h"
#include "ops.h"
#include "pegbus.h"
#include "types.h"
#include "z80.h"

#define NR_CPUS		2
#define NR_PAGES	64

typedef struct
{
	uint8_t page[NR_CPUS][16];
	bool iospace[NR_CPUS][16];
	int8_t lock, using[NR_PAGES];
	uint8_t irq_owner[128];
	bool dd[NR_CPUS];
}
mmu_t;

#define PROGRAM	"pegbox/kernel.bin"

#define IO_TIMER	0x02
#define IO_MMU		0x04
# define IO_MMU_GETPAGE	0
# define IO_MMU_GETPROT	1
# define IO_MMU_GETCPUID	2
#define IO_TERMINAL	0x10

#define TTY_BUF_LEN	128

#define FRAME_LEN	350000 /* 1/10 of a second at 3.5MHz */

int main(void)//int argc, char * argv[])
{
	// State
	z80 cpu[NR_CPUS];
	uint8_t irq[NR_CPUS];
	bus_t cbus[NR_CPUS], rbus[NR_PAGES];
	ram_page ram[NR_PAGES];
	mmu_t mmu;
#define IRQ_OWNER(_irq)	mmu.irq_owner[(_irq)>>1]
#define IRQ(_irq)	interrupt(IRQ_OWNER(_irq), (_irq))
#define interrupt(ci, _irq)	do { \
	if (!irq[(ci)] || (_irq) < irq[(ci)]) \
		irq[(ci)]=(_irq);\
	} while(0);
	for(uint8_t page=0;page<NR_PAGES;page++)
	{
		mmu.using[page]=-1;
		memset(ram[page], 0, sizeof(ram[page]));
		bus_reset(&rbus[page]);
	}
	mmu.lock=-1;
	for(uint8_t ci=0;ci<NR_CPUS;ci++)
	{
		irq[ci]=0;
		z80_reset(&cpu[ci], &cbus[ci]);
		bus_reset(&cbus[ci]);
		for(uint8_t pi=0;pi<16;pi++)
		{
			mmu.page[ci][pi]=0;
			mmu.iospace[ci][pi]=false;
		}
	}
	// Attach pegbus devices
	int pb_test_dev=pegbus_attach_device(0xff0d, 5, pegbus_test_read_trap, pegbus_test_write_trap);
	if(pb_test_dev<0)
		fprintf(stderr, "Failed to attach test device to pegbus: %s\n", strerror(pb_test_dev));
	z80_init(); // initialise decoding tables
	int prog=open(PROGRAM, O_RDONLY);
	if(prog<0)
	{
		perror("Failed to load kernel: open");
		return(1);
	}
	for(uint8_t page=0;page<NR_PAGES;page++)
	{
		ssize_t bytes=read(prog, ram[page], sizeof(ram[page]));
		if(bytes>0)
			fprintf(stderr, "Page %02x: %zd bytes\n", page, bytes);
		else
			break;
	}
	close(prog);
	char tty_buf[TTY_BUF_LEN];
	int tty_buf_wp=0, tty_buf_rp=0;
	int tty_T=0;
	int errupt=0;
	int T=0;
#ifdef LOCK_DEBUG
	bool lockmap[0x1000];
#endif
	bool can_progress; // _someone_ isn't WAITed
	bool work_to_do; // _someone_ isn't DI HALT
	while(!errupt)
	{
		if(tty_buf_wp!=tty_buf_rp)
			IRQ(IO_TERMINAL);
		for(unsigned int slot=0;slot<PB_MAX_DEV;slot++)
		{
			if(pbdevs[slot].irq)
			{
				if(pbdevs[slot].config.command==PB_CMD_SHUTUP) // enforce good pegbus behaviour
				{
					fprintf(stderr, "Warning: pegbus device %04x (slot %x) didn't SHUTUP\n", pbdevs[slot].config.device_id, slot);
					pbdevs[slot].irq=false;
				}
				else
				{
					IRQ(IO_PEGBUS+(slot*2));
				}
			}
		}
		for(uint8_t ci=0;ci<NR_CPUS;ci++)
		{
			/* Timer interrupt, staggered across CPUs.  Must be highest priority, as cannot be dropped */
			if(T==(((int32_t)ci)<<12))
			{
				irq[ci]=IO_TIMER;
				//fprintf(stderr, "Raised IRQ_TIMER on %u\n", ci);
			}
			if((cbus[ci].irq=irq[ci]))
			{
				if(cpu[ci].intacc)
				{
					cbus[ci].data=irq[ci];
					//fprintf(stderr, "Acknowledged IRQ %u on %u\n", irq[ci], ci);
					if(irq[ci]>=IO_PEGBUS&&irq[ci]<IO_PEGBUS+PB_MAX_DEV*2)
					{
						unsigned int slot=(irq[ci]-IO_PEGBUS)/2;
						pbdevs[slot].irq=false;
					}
					irq[ci]=0;
				}
			}
			if((errupt=z80_tstep(&cpu[ci], &cbus[ci], errupt))) break;
			/* IO devices */
			if(cbus[ci].iorq&&cbus[ci].tris)
			{
				uint8_t port=cbus[ci].addr&0xff;
				if(!port) // IO control
				{
					if(cbus[ci].tris==TRIS_OUT)
					{
						mmu.irq_owner[cbus[ci].data>>1]=ci;
					}
				}
				else if(port==IO_MMU)
				{
					if(cbus[ci].tris==TRIS_IN)
					{
						int pi=(cbus[ci].addr>>8)&0xf;
						int cmd=cbus[ci].addr>>12;
						uint8_t rv;
						switch(cmd)
						{
							case IO_MMU_GETPAGE: // get current page
								rv=mmu.page[ci][pi];
							break;
							case IO_MMU_GETPROT: // get prot bits and IO
								rv=0xfc; // for now, all types of access are always permitted
								if(mmu.iospace[ci][pi])
									rv|=2;
								break;
							case IO_MMU_GETCPUID: // get cpu socket ID
								rv=ci;
							break;
							default:
								rv=0xff;
							break;
						}
						cbus[ci].data=rv;
					}
					else
					{
						if(cbus[ci].addr&0x8000) // set prot bits
						{
							// is a nop for now
						}
						else
						{
							int pi=(cbus[ci].addr>>8)&0xf;
							mmu.page[ci][pi]=cbus[ci].data;
							mmu.iospace[ci][pi]=cbus[ci].addr&0x4000;
						}
					}
				}
				else if(port==IO_TERMINAL)
				{
					if(cbus[ci].tris==TRIS_IN)
					{
						if(tty_buf_wp!=tty_buf_rp)
						{
							cbus[ci].data=tty_buf[tty_buf_rp++];
							tty_buf_rp%=TTY_BUF_LEN;
						}
					}
					else if(T!=((tty_T+1)%FRAME_LEN))
					{
						putchar(cbus[ci].data);
						if(cbus[ci].data==0x0a)
							fflush(stdout);
						tty_T=T;
					}
				}
			}
			/* MMU */
			for(uint8_t pi=0;pi<16;pi++)
			{
				if(mmu.iospace[ci][pi])
					continue;
				uint8_t page=mmu.page[ci][pi];
				if(page<NR_PAGES&&mmu.using[page]==ci)
					mmu.using[page]=-1;
			}
			if(cbus[ci].mreq&&cbus[ci].tris)
			{
				uint8_t pi=cbus[ci].addr>>12;
				uint8_t page=mmu.page[ci][pi];
				if(mmu.iospace[ci][pi])
				{
					uint16_t addr=cbus[ci].addr&0xfff;
					uint8_t slot=page>>4;
					page&=0xf;
					addr|=(page<<12);
					if(slot<PB_MAX_DEV && pbdevs[slot].attached)
					{
						if(cbus[slot].tris==TRIS_OUT)
						{
							uint8_t data=cbus[ci].data;
							if(addr<pbdevs[slot].trap_addr&&pbdevs[slot].write)
								data=pbdevs[slot].write(pbdevs+slot, addr, cbus[ci].data);
							pbdevs[slot].raw[page][addr]=data;
						}
						else /* TRIS_IN */
						{
							uint8_t data=pbdevs[slot].raw[page][addr];
							if(addr<pbdevs[slot].trap_addr&&pbdevs[slot].read)
								data=pbdevs[slot].read(pbdevs+slot, addr, data);
							cbus[ci].data=data;
						}
					}
					else /* no device */
					{
						cbus[ci].data=0xff;
					}
				}
				else
				{
					if(mmu.lock>=0 && mmu.lock!=ci)
					{
						cbus[ci].waitline=true;
					}
					else if(page<NR_PAGES)
					{
						if(mmu.using[page]<0)
						{
							mmu.using[page]=ci;
							/* MMU */
							rbus[page].tris=cbus[ci].tris;
							rbus[page].addr=cbus[ci].addr&0xfff;
							if(rbus[page].tris==TRIS_OUT)
								rbus[page].data=cbus[ci].data;
							/* RAM */
							if(rbus[page].tris==TRIS_IN)
							{
								rbus[page].data=ram[page][rbus[page].addr];
							}
							else
							{
								ram[page][rbus[page].addr]=rbus[page].data;
#ifdef DEBUG_WRITES
								if(!ci)
									fprintf(stderr, "%02x: %s %04x [%02x:%04x] %02x\n", ci, cbus[ci].tris==TRIS_IN?"RD":"WR", cbus[ci].addr, page, rbus[page].addr, rbus[page].data);
#endif
							}
							/* and MMU again */
							if(rbus[page].tris==TRIS_IN)
							{
								cbus[ci].data=rbus[page].data;
								if(cbus[ci].data==0xdd)
								{
									if(mmu.dd[ci])
									{
										mmu.lock=ci;
									}
									else if(cbus[ci].m1)
										mmu.dd[ci]=true;
								}
								else
									mmu.dd[ci]=false;
							}
							else if(mmu.lock==ci)
							{
								mmu.lock=-1;
#ifdef LOCK_DEBUG
								if(cbus[ci].addr<0x1000 && page==0 && !lockmap[cbus[ci].addr])
									fprintf(stderr, "%02x: ACQ %04x [%02x:%04x]\n", ci, cbus[ci].addr, page, rbus[page].addr);
								lockmap[cbus[ci].addr]=true;
#endif
							}
#ifdef LOCK_DEBUG
							if(cbus[ci].addr<0x1000 && page==0 && lockmap[cbus[ci].addr] && cbus[ci].data==0xfe)
								fprintf(stderr, "%02x: %s %04x [%02x:%04x]\n", ci, cbus[ci].tris==TRIS_IN?"ACQ":"REL", cbus[ci].addr, page, rbus[page].addr);
#endif
							cbus[ci].waitline=false;
						}
						else
						{
							cbus[ci].waitline=true;
						}
					}
					else if(cbus[ci].tris==TRIS_IN)
					{
						cbus[ci].data=0xff;
					}
				}
			}
		}
		/* Check for hw deadlock (shouldn't happen) */
		can_progress=false;
		for(uint8_t ci=0;ci<NR_CPUS;ci++)
			if(!cbus[ci].waitline)
				can_progress=true;
		if(!can_progress)
		{
			fprintf(stderr, "Deadlock!\n");
			for(uint8_t ci=0;ci<NR_CPUS;ci++)
				if(cbus[ci].mreq&&cbus[ci].tris)
				{
					uint8_t pi=cbus[ci].addr>>12;
					uint8_t page=mmu.page[ci][pi];
					if(mmu.iospace[page]) // should be impossible as MMIO is not locked or serialised
					{
						fprintf(stderr, "%02x: %s %04x %02x\n", ci, cbus[ci].tris==TRIS_IN?"IN":"OUT", cbus[ci].addr, cbus[ci].data);
					}
					else
					{
						if(page<NR_PAGES&&mmu.using[page]<0)
							fprintf(stderr, "%02x: %s %04x %02x\n", ci, cbus[ci].tris==TRIS_IN?"RD":"WR", cbus[ci].addr, cbus[ci].data);
						else
							fprintf(stderr, "%02x: WAIT %02x (%04x)\n", ci, page, cbus[ci].addr);
					}
				}
			break;
		}
		/* Check for hw stopped (everyone DI HALT, eg. after panic()) */
		work_to_do=false;
		for(uint8_t ci=0;ci<NR_CPUS;ci++)
			if(cpu[ci].IFF[0]||!cpu[ci].halt||cpu[ci].intacc)
				work_to_do=true;
		if(!work_to_do)
		{
			fprintf(stderr, "Powerdown!\n");
			for(uint8_t ci=0;ci<NR_CPUS;ci++)
			{
				uint16_t pc=cpu[ci].regs[0]|(cpu[ci].regs[1]<<8);
				fprintf(stderr, "%02x: PC = %04x, IFF %d %d\n", ci, pc, cpu[ci].IFF[0], cpu[ci].IFF[1]);
			}
			break;
		}
		if(++T>=FRAME_LEN)
			T-=FRAME_LEN;
	}
	return(0);
}
