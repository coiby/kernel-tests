#include<stdio.h>
#include<unistd.h>
#include<stdlib.h>
#include<sys/stat.h>

int result=0;
unsigned int do_nhm_cstates;
unsigned int do_snb_cstates;
unsigned int do_nehalem_platform_info;
unsigned int genuine_intel;
unsigned int has_invariant_tsc;
unsigned int has_aperf;

int is_snb(unsigned int family, unsigned int model)
{
	if (!genuine_intel)
		return 0;

	switch (model) {
		case 0x2A:
		case 0x2D:
			return 1;
	}
	return 0;
}

void check_dev_msr()
{
	struct stat sb;

	if (stat("/dev/cpu/0/msr", &sb)) {
		fprintf(stderr, "no /dev/cpu/0/msr\n");
		fprintf(stderr, "Try \"# modprobe msr\"\n");
		result = 1;
		return;
	}
}

void check_cpuid(void)
{
	unsigned int eax, ebx, ecx, edx, max_level;
	unsigned int fms, family, model, stepping;

	__asm__ volatile ("cpuid"
			:"=a" (max_level), "=b" (ebx), "=c" (ecx), "=d" (edx)
			:"a" (0));

	if (ebx == 0x756e6547 && edx == 0x49656e69 && ecx == 0x6c65746e)
		genuine_intel = 1;

	asm("cpuid" : "=a" (fms), "=c" (ecx), "=d" (edx) : "a" (1) : "ebx");
	family = (fms >> 8) & 0xf;
	model = (fms >> 4) & 0xf;
	stepping = fms & 0xf;
	if (family == 6 || family == 0xf)
		model += ((fms >> 16) & 0xf) << 4;

	if (!(edx & (1 << 5))) {
		fprintf(stderr, "CPUID: no MSR\n");
		result = 1;
		return;
	}

	/*
	 * check max extended function levels of CPUID.
	 * This is needed to check for invariant TSC.
	 * This check is valid for both Intel and AMD.
	 */
	ebx = ecx = edx = 0;
	asm("cpuid" : "=a" (max_level), "=b" (ebx), "=c" (ecx), "=d" (edx) : "a" (0x80000000));

	if (max_level < 0x80000007) {
		fprintf(stderr, "CPUID: no invariant TSC (max_level 0x%x)\n", max_level);
		result = 1;
		return;
	}

	/*
	 * Non-Stop TSC is advertised by CPUID.EAX=0x80000007: EDX.bit8
	 * this check is valid for both Intel and AMD
	 */
	asm("cpuid" : "=a" (eax), "=b" (ebx), "=c" (ecx), "=d" (edx) : "a" (0x80000007));
	has_invariant_tsc = edx && (1 << 8);

	if (!has_invariant_tsc) {
		fprintf(stderr, "No invariant TSC\n");
		result = 1;
		return;
	}

	/*
	 * APERF/MPERF is advertised by CPUID.EAX=0x6: ECX.bit0
	 * this check is valid for both Intel and AMD
	 */

	asm("cpuid" : "=a" (eax), "=b" (ebx), "=c" (ecx), "=d" (edx) : "a" (0x6));
	has_aperf = ecx && (1 << 0);
	if (!has_aperf) {
		fprintf(stderr, "No APERF MSR\n");
		result = 1;
		return;
	}

	do_nehalem_platform_info = genuine_intel && has_invariant_tsc;
	do_nhm_cstates = genuine_intel; /* all Intel w/ non-stop TSC have NHM counters */
	do_snb_cstates = is_snb(family, model);
}

void main(int argc,char *argv[])
{
	if (argc >1)
	{
		fprintf(stderr,"error option . just checking\n");
		exit(1);
	}

	// checking now ...  
	check_cpuid();

	if (!result) {
		fprintf(stdout,"CPUID checking ok ...\n");
		// checking dev msr
		check_dev_msr();
		if (!result) {
			fprintf(stdout,"checking Successfully!\nsupport:\n");
			if (do_nhm_cstates)
				fprintf(stdout,"\tNHM-cstates ...\n");
			if (do_snb_cstates)
				fprintf(stdout,"\tSNB-cstates ...\n");

			exit(0);
		}
		else {
			fprintf(stderr,"Platform does not support ...\n");
			exit(2);
		}
	}
	else {
		fprintf(stderr,"Platform does not support ...\n");
		exit(2);
	}
}
