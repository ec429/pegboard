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
#include "z80.h"

#define NR_CPUS		2
#define NR_PAGES	64

typedef uint8_t ram_page[0x1000];

typedef struct
{
	uint8_t page[NR_CPUS][16];
	bool iospace[NR_CPUS][16];
	int8_t lock, using[NR_PAGES];
	bool dd[NR_CPUS];
}
mmu_t;

#define PROGRAM	"os/kernel.bin"

#define IO_TIMER	0x02
#define IO_MMU		0x04
#define IO_TERMINAL	0x10

#define interrupt(ci, _irq)	do { \
	if (!irq[ci] || _irq < irq[ci]) \
		irq[ci]=_irq;\
	} while(0);

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
	z80_init(); // initialise decoding tables
	int prog=open(PROGRAM, O_RDONLY);
	for(uint8_t page=0;page<NR_PAGES;page++)
	{
		ssize_t bytes=read(prog, ram[page], sizeof(ram[page]));
		if(bytes>0)
			fprintf(stderr, "Page %02x: %zd bytes\n", page, bytes);
		else
			break;
	}
	close(prog);
	uint8_t tty_owner=0;
	char tty_buf[TTY_BUF_LEN];
	int tty_buf_wp=0, tty_buf_rp=0;
	int tty_T=0;
	int errupt=0;
	int T=0;
#ifdef LOCK_DEBUG
	bool lockmap[32768];
#endif
	bool can_progress; // _someone_ isn't WAITed
	bool work_to_do; // _someone_ isn't DI HALT
	while(!errupt)
	{
		if(tty_buf_wp!=tty_buf_rp)
			interrupt(tty_owner, IO_TERMINAL);
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
						switch(cbus[ci].data)
						{
							case IO_TERMINAL:
								tty_owner=ci;
							break;
							default:
							break;
						}
					}
				}
				else if(port==IO_MMU)
				{
					if(cbus[ci].tris==TRIS_IN)
					{
						int pi=(cbus[ci].addr>>8)&0xf;
						if(cbus[ci].addr&0x8000) // get prot bits and IO
						{
							cbus[ci].data=0xfc; // for now, all types of access are always permitted
							if(mmu.iospace[ci][pi])
								cbus[ci].data|=2;
						}
						else // get current page
						{
							cbus[ci].data=mmu.page[ci][pi];
						}
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
				if(mmu.lock>=0 && mmu.lock!=ci)
				{
					cbus[ci].waitline=true;
				}
				else
				{
					uint8_t pi=cbus[ci].addr>>12;
					uint8_t page=mmu.page[ci][pi];
					if(mmu.iospace[ci][pi])
					{
						// No MMIO devices implemented yet
						cbus[ci].data=0xff;
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
								if(!lockmap[cbus[ci].addr])
									fprintf(stderr, "%02x: ACQ %04x [%02x:%04x]\n", ci, cbus[ci].addr, page, rbus[page].addr);
								lockmap[cbus[ci].addr]=true;
#endif
							}
#ifdef LOCK_DEBUG
							if(lockmap[cbus[ci].addr] && cbus[ci].data==0xfe)
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
