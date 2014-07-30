/*
	m80em - emulator for multi80, hypothetical SMP Z80 machine
	
	Copyright Edward Cree, 2010-13
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

#define NR_CPUS		1
#define NR_PAGES	64

typedef uint8_t ram_page[16384];

typedef struct
{
	uint8_t page[NR_CPUS][4];
	int8_t lock, using[NR_PAGES];
	bool dd[NR_CPUS];
}
mmu_t;

#define PROGRAM	"os/main.bin"

#define IO_MMU		0x05
#define	 MM_SETPAGE	0x00
#define	 MM_GETPAGE	0x01
#define IO_TERMINAL	0x10

#define TTY_BUF_LEN	128

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
		for(uint8_t pi=0;pi<4;pi++)
			mmu.page[ci][pi]=0;
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
	int T=0, maxT=1<<24;
#ifdef LOCK_DEBUG
	bool lockmap[32768];
#endif
	bool can_progress; // _someone_ isn't WAITed
	while(!errupt)
	{
		if(!irq[tty_owner] && (tty_buf_wp!=tty_buf_rp))
			irq[tty_owner]=IO_TERMINAL;
		for(uint8_t ci=0;ci<NR_CPUS;ci++)
		{
			if((cbus[ci].irq=irq[ci]))
			{
				if(cpu[ci].intacc)
					cbus[ci].data=irq[ci];
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
					uint8_t cmd=cbus[ci].addr>>10; // command
					uint8_t pi=(cbus[ci].addr>>8)&3; // vpage
					if(cbus[ci].tris==TRIS_IN)
					{
						if(cmd==MM_GETPAGE)
						{
							cbus[ci].data=mmu.page[ci][pi];
						}
						else
						{
							cbus[ci].data=0xff;
						}
					}
					else
					{
						if(cmd==MM_SETPAGE)
						{
							mmu.page[ci][pi]=cbus[ci].data;
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
					else if(T>tty_T+1)
					{
						putchar(cbus[ci].data);
						tty_T=T;
					}
				}
			}
			/* MMU */
			for(uint8_t pi=0;pi<4;pi++)
			{
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
					uint8_t pi=cbus[ci].addr>>14;
					uint8_t page=mmu.page[ci][pi];
					if(page<NR_PAGES)
					{
						if(mmu.using[page]<0)
						{
							mmu.using[page]=ci;
							/* MMU */
							rbus[page].tris=cbus[ci].tris;
							rbus[page].addr=cbus[ci].addr&0x3fff;
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
								if(cbus[ci].addr<0x1000)
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
								lockmap[cbus[ci].addr]=true;
#endif
							}
#ifdef LOCK_DEBUG
							if(lockmap[cbus[ci].addr])
								fprintf(stderr, "%02x: %s %04x [%02x:%04x] %02x\n", ci, cbus[ci].tris==TRIS_IN?"RD":"WR", cbus[ci].addr, page, rbus[page].addr, cbus[ci].data);
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
					uint8_t pi=cbus[ci].addr>>14;
					uint8_t page=mmu.page[ci][pi];
					if(page<NR_PAGES&&mmu.using[page]<0)
						fprintf(stderr, "%02x: %s %04x %02x\n", ci, cbus[ci].tris==TRIS_IN?"RD":"WR", cbus[ci].addr, cbus[ci].data);
					else
						fprintf(stderr, "%02x: WAIT %02x (%04x)\n", ci, page, cbus[ci].addr);
				}
			break;
		}
		if(T++>=maxT) break;
	}
	return(0);
}
