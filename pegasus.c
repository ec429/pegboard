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
#include <signal.h>
#include "bits.h"
#include "ops.h"
#include "pegbus.h"
#include "types.h"
#include "z80.h"
#include "virt-disk.h"

/* maxima for -c and -p */
#define MAX_CPUS	128
#define MAX_PAGES	256

/* default for -c and -p */
#define NR_CPUS		2
#define NR_PAGES	64

typedef struct
{
	uint8_t page[MAX_CPUS][16];
	bool iospace[MAX_CPUS][16];
	int8_t lock, using[MAX_PAGES];
	uint8_t irq_owner[128];
	bool dd[MAX_CPUS];
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

volatile sig_atomic_t siginted=0;

void sigint_handler(__attribute__((unused)) int sig)
{
	siginted=1;
}

int main(int argc, char * argv[])
{
	unsigned int nr_cpus=NR_CPUS, nr_pages=NR_PAGES;
	const char *disk_file=NULL;
	const char *core_file=NULL;
	unsigned int core_page=0;
	for(int arg=1;arg<argc;arg++)
	{
		if(argv[arg][0]=='-')
		{
			int bytes;
			switch(argv[arg][1])
			{
				case 'c':
					if(sscanf(argv[arg]+2, "%u", &nr_cpus)!=1)
					{
						fprintf(stderr, "Bad -c value %s\n", argv[arg]+2);
						return(2);
					}
					if(nr_cpus>MAX_CPUS)
					{
						fprintf(stderr, "-c value %u too large, max is %u\n", nr_cpus, MAX_CPUS);
						return(2);
					}
				break;
				case 'p':
					if(sscanf(argv[arg]+2, "%u", &nr_pages)!=1)
					{
						fprintf(stderr, "Bad -p value %s\n", argv[arg]+2);
						return(2);
					}
					if(nr_pages>MAX_PAGES)
					{
						fprintf(stderr, "-p value %u too large, max is %u\n", nr_pages, MAX_PAGES);
						return(2);
					}
				break;
				case 'd':
					disk_file=argv[arg]+2;
				break;
				case 'C':
					if(sscanf(argv[arg]+2, "%u%n", &core_page, &bytes)<1)
					{
						fprintf(stderr, "Bad -C value %s\n", argv[arg]+2);
						return(2);
					}
					if(core_page>MAX_PAGES)
					{
						fprintf(stderr, "-C value %u too large, max is %u\n", core_page, MAX_PAGES);
						return(2);
					}
					if(argv[arg][2+bytes]!=',')
					{
						fprintf(stderr, "-C value %s missing comma\n", argv[arg]+2);
						return(2);
					}
					core_file=argv[arg]+bytes+3;
				break;
				default:
					fprintf(stderr, "Unrecognised option %s\n", argv[arg]);
					return(2);
				break;
			}
		}
	}
	// State
	z80 cpu[MAX_CPUS];
	uint8_t irq[MAX_CPUS];
	bool irqprime[MAX_CPUS];
	bus_t cbus[MAX_CPUS], rbus[MAX_PAGES];
	ram_page ram[MAX_PAGES];
	mmu_t mmu;
#define IRQ_OWNER(_irq)	mmu.irq_owner[(_irq)>>1]
#define IRQ(_irq)	interrupt(IRQ_OWNER(_irq), (_irq))
#define interrupt(ci, _irq)	do { \
	if (!irq[(ci)] || (_irq) < irq[(ci)]) \
		irq[(ci)]=(_irq);\
	} while(0);
	for(unsigned int page=0;page<MAX_PAGES;page++)
	{
		mmu.using[page]=-1;
		memset(ram[page], 0, sizeof(ram[page]));
		bus_reset(&rbus[page]);
	}
	mmu.lock=-1;
	for(int ci=0;ci<MAX_CPUS;ci++)
	{
		irq[ci]=0;
		irqprime[ci]=true;
		z80_reset(&cpu[ci], &cbus[ci]);
		bus_reset(&cbus[ci]);
		for(uint8_t pi=0;pi<16;pi++)
		{
			mmu.page[ci][pi]=0;
			mmu.iospace[ci][pi]=false;
		}
	}
	// Attach pegbus devices
	int pb_test_dev=pegbus_attach_device(0xff0d, 5, pegbus_test_read_trap, pegbus_test_write_trap, NULL, NULL);
	if(pb_test_dev<0)
		fprintf(stderr, "Failed to attach test device to pegbus: %s\n", strerror(pb_test_dev));
	int diskfd=-1, pb_disk_dev=-1;
	if(disk_file)
	{
		diskfd=open(disk_file, O_RDWR);
		if(diskfd<0)
		{
			perror("Failed to mount virt-disk: open");
			return(1);
		}
		pb_disk_dev=virt_disk_attach(diskfd);
		if(pb_disk_dev<0)
		{
			fprintf(stderr, "Failed to attach virt-disk device to pegbus: %s\n", strerror(pb_disk_dev));
			return(1);
		}
		fprintf(stderr, "Attached disk (image %s) in slot %d\n", disk_file, pb_disk_dev);
	}
	z80_init(); // initialise decoding tables
	int prog=open(PROGRAM, O_RDONLY);
	if(prog<0)
	{
		perror("Failed to load kernel: open");
		return(1);
	}
	for(unsigned int page=0;page<nr_pages;page++)
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
	bool lockmap[MAX_PAGES][0x1000];
#endif
	bool can_progress; // _someone_ isn't WAITed
	bool work_to_do; // _someone_ isn't DI HALT
	if(signal(SIGINT, sigint_handler)==SIG_ERR)
	{
		perror("Failed to wire SIGINT: signal");
		return(1);
	}
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
		for(unsigned int page=0;page<nr_pages;page++)
		{
			if(mmu.using[page]!=mmu.lock)
				mmu.using[page]=-1;
		}
		for(int ci=0;ci<(int)nr_cpus;ci++)
		{
			/* Timer interrupt, staggered across CPUs.  Must be highest priority, as cannot be dropped */
			if(T==(((int32_t)ci)<<10))
			{
				irq[ci]=IO_TIMER;
				//fprintf(stderr, "Raised IRQ_TIMER on %u\n", ci);
			}
			if((cbus[ci].irq=irq[ci]))
			{
				if(cpu[ci].intacc)
				{
					if(irqprime[ci])
					{
						cbus[ci].data=irq[ci];
						//fprintf(stderr, "Acknowledged IRQ %u on %u at %u\n", irq[ci], ci, T);
						if(irq[ci]>=IO_PEGBUS&&irq[ci]<IO_PEGBUS+PB_MAX_DEV*2)
						{
							unsigned int slot=(irq[ci]-IO_PEGBUS)/2;
							pbdevs[slot].irq=false;
						}
						irq[ci]=0;
						irqprime[ci]=false;
					}
				}
				else
				{
					irqprime[ci]=true;
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
					if(page<nr_pages)
					{
						if(mmu.using[page]<0 || mmu.using[page]==ci)
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
										if(mmu.lock>=0 && mmu.lock!=ci)
										{
											goto mmu_wait;
										}
										else
										{
											mmu.lock=ci;
										}
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
								if(!lockmap[page][rbus[page].addr])
									fprintf(stderr, "%02x: ACQ %04x [%02x:%04x]\n", ci, cbus[ci].addr, page, rbus[page].addr);
								lockmap[page][rbus[page].addr]=true;
#endif
							}
#ifdef LOCK_DEBUG
							if(lockmap[page][rbus[page].addr] && cbus[ci].data==0xfe)
								fprintf(stderr, "%02x: %s %04x [%02x:%04x]\n", ci, cbus[ci].tris==TRIS_IN?"ACQ":"REL", cbus[ci].addr, page, rbus[page].addr);
#endif
							cbus[ci].waitline=false;
						}
						else
						{
							mmu_wait:
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
		for(int ci=0;ci<(int)nr_cpus;ci++)
			if(!cbus[ci].waitline)
				can_progress=true;
		if(!can_progress)
		{
			fprintf(stderr, "Deadlock!\n");
			fprintf(stderr, "mmu.lock=%02x\n", mmu.lock);
			for(int ci=0;ci<(int)nr_cpus;ci++)
				if(cbus[ci].mreq&&cbus[ci].tris)
				{
					uint8_t pi=cbus[ci].addr>>12;
					uint8_t page=mmu.page[ci][pi];
					if(mmu.iospace[ci][pi]) // should be impossible as MMIO is not locked or serialised
					{
						fprintf(stderr, "%02x: %s %04x %02x\n", ci, cbus[ci].tris==TRIS_IN?"IN":"OUT", cbus[ci].addr, cbus[ci].data);
					}
					else
					{
						if(page<nr_pages&&mmu.using[page]<0)
							fprintf(stderr, "%02x: %s %04x %02x\n", ci, cbus[ci].tris==TRIS_IN?"RD":"WR", cbus[ci].addr, cbus[ci].data);
						else
							fprintf(stderr, "%02x: WAIT %02x (for %02x) (addr %04x)\n", ci, page, mmu.using[page], cbus[ci].addr);
					}
				}
			break;
		}
		/* Check for hw stopped (everyone DI HALT, eg. after panic()) */
		work_to_do=false;
		for(int ci=0;ci<(int)nr_cpus;ci++)
			if(cpu[ci].IFF[0]||!cpu[ci].halt||cpu[ci].intacc)
				work_to_do=true;
		if(!work_to_do)
		{
			fprintf(stderr, "Powerdown!\n");
			pcstate:
			for(int ci=0;ci<(int)nr_cpus;ci++)
			{
				uint16_t pc=cpu[ci].regs[0]|(cpu[ci].regs[1]<<8);
				fprintf(stderr, "%02x: PC = %04x, IFF %d %d\n", ci, pc, cpu[ci].IFF[0], cpu[ci].IFF[1]);
			}
			break;
		}
		if(siginted)
		{
			fprintf(stderr, "Interrupted!\n");
			goto pcstate;
		}
		if(++T>=FRAME_LEN)
			T-=FRAME_LEN;
	}
	if(core_file)
	{
		int corefd=creat(core_file, 0644);
		if(corefd<0)
		{
			perror("core_file: fopen");
		}
		else
		{
			if(write(corefd, ram[core_page], sizeof(ram_page))<(ssize_t)sizeof(ram_page))
				perror("core_file: write");
			else
				fprintf(stderr, "Core page %u written to %s\n", core_page, core_file);
			close(corefd);
		}
	}
	return(0);
}
