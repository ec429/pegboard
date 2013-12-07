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

#define NR_CPUS		8
#define NR_PAGES	4

typedef uint8_t ram_page[16384];

typedef struct
{
	uint8_t page[NR_CPUS][4];
	int8_t lock, using[NR_PAGES];
	bool dd[NR_CPUS];
}
mmu_t;

#define PROGRAM	"locktest.bin"

#define namelock	0x3c
#define slotlock	0x3d

int main(void)//int argc, char * argv[])
{
	// State
	z80 cpu[NR_CPUS];
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
		z80_reset(&cpu[ci], &cbus[ci]);
		bus_reset(&cbus[ci]);
		for(uint8_t pi=0;pi<4;pi++)
			mmu.page[ci][pi]=pi;
	}
	z80_init(); // initialise decoding tables
	int prog=open(PROGRAM, O_RDONLY);
	ssize_t bytes=read(prog, ram[0], sizeof(ram[0]));
	fprintf(stderr, "Program: %zd bytes\n", bytes);
	close(prog);
	int errupt=0;
	int T=0, maxT=8192;
	while(!errupt)
	{
		for(uint8_t ci=0;ci<NR_CPUS;ci++)
		{
			if((errupt=z80_tstep(&cpu[ci], &cbus[ci], errupt))) break;
			for(uint8_t pi=0;pi<4;pi++)
			{
				uint8_t page=mmu.page[ci][pi];
				if(mmu.using[page]==ci)
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
							rbus[page].data=ram[page][rbus[page].addr];
						else
							ram[page][rbus[page].addr]=rbus[page].data;
						/* and MMU again */
						if(rbus[page].tris==TRIS_IN)
						{
							cbus[ci].data=rbus[page].data;
							if(cbus[ci].data==0xdd)
							{
								if(mmu.dd[ci])
								{
									mmu.lock=ci;
									fprintf(stderr, "%02x: LOCK\n", ci);
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
							fprintf(stderr, "%02x: UNLOCK\n", ci);
						}
						fprintf(stderr, "%02x: %s %04x [%02x:%04x] %02x\n", ci, cbus[ci].tris==TRIS_IN?"RD":"WR", cbus[ci].addr, page, rbus[page].addr, cbus[ci].data);
						if(cbus[ci].tris==TRIS_OUT && (cbus[ci].addr==namelock || cbus[ci].addr==slotlock))
							fprintf(stderr, "    %s, %s\n", ram[0][namelock]^0xfe?"NAME":"name", ram[0][slotlock]^0xfe?"SLOT":"slot");
						cbus[ci].waitline=false;
					}
					else
					{
						cbus[ci].waitline=true;
					}
				}
			}
		}
		bool can_progress=false;
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
					if(mmu.using[page]<0)
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
