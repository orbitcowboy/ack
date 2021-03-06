/*
 * (c) copyright 1987 by the Vrije Universiteit, Amsterdam, The Netherlands.
 * See the copyright notice in the ACK home directory, in the file "Copyright".
 *
 */

/*
 * machine dependent back end routines for the PowerPC
 */

#include <limits.h>
#include <stdint.h>

static long framesize;

con_part(int sz, word w)
{
	while (part_size % sz)
		part_size++;
	if (part_size == TEM_WSIZE)
		part_flush();
	if (sz == 1) {
		w &= 0xFF;
		w <<= 8 * (3 - part_size);
		part_word |= w;
	} else if (sz == 2) {
		w &= 0xFFFF;
		w <<= 8 * (2 - part_size);
		part_word |= w;
	} else {
		assert(sz == 4);
		part_word = w;
	}
	part_size += sz;
}

con_mult(word sz)
{

	if (argval != 4)
		fatal("bad icon/ucon size");
	fprintf(codefile,".data4 %s\n", str);
}

#define CODE_GENERATOR  
#define IEEEFLOAT  
#define FL_MSL_AT_LOW_ADDRESS	1
#define FL_MSW_AT_LOW_ADDRESS	1
#define FL_MSB_AT_LOW_ADDRESS	1
#include <con_float>

static void
emit_prolog(void)
{
	fprintf(codefile, "mfspr r0, lr\n");
	fprintf(codefile, "addi sp, sp, %ld\n", -framesize - 8);
	fprintf(codefile, "stw fp, %ld(sp)\n", framesize);
	fprintf(codefile, "stw r0, %ld(sp)\n", framesize + 4);
	fprintf(codefile, "addi fp, sp, %ld\n", framesize);
}

void
prolog(full nlocals)
{
	framesize = nlocals;

#ifdef REGVARS
	/* f_regsave() will call emit_prolog() */
#else
	emit_prolog();
#endif
}

void
mes(word type)
{
	int argt ;

	switch ( (int)type ) {
	case ms_ext :
		for (;;) {
			switch ( argt=getarg(
			    ptyp(sp_cend)|ptyp(sp_pnam)|sym_ptyp) ) {
			case sp_cend :
				return ;
			default:
				strarg(argt) ;
				fprintf(codefile,".define %s\n",argstr) ;
				break ;
			}
		}
	default :
		while ( getarg(any_ptyp) != sp_cend ) ;
		break ;
	}
}

char *segname[] = {
	".sect .text",
	".sect .data",
	".sect .rom",
	".sect .bss"
};

#ifdef REGVARS

static long savedf[32];
static long savedi[32];
static int savedtop;
static uint32_t lfs_set;

/* Calculate the register score of a local variable. */
int
regscore(long offset, int size, int type, int frequency, int totype)
{
	int score;

	switch (type) {
		case reg_float:
			/* Don't put reg_float in reg_any. */
			if (totype != reg_float)
				return -1;
			assert(size == 4 || size == 8);
			break;
		default:
			assert(size == 4);
			break;
	}

	/* Clamp to avoid overflowing 16-bit int score. */
	if (frequency > 8000)
		frequency = 8000;

	/*
	 * Each occurence of a regvar saves about 4 bytes by not
	 * emitting a load or store instruction.  The overhead is
	 * about 8 bytes to save and restore the register, plus
	 * 4 bytes if the local is a parameter.
	 */
	score = 4 * frequency - 8 - ((offset >= 0) ? 4 : 0);
#if 0
	fprintf(codefile, "! local %ld score %d\n", offset, score);
#endif
	return score;
}

/* Initialise regvar system for one function. */

i_regsave(void)
{
	int i;

	for (i=0; i<32; i++) {
		savedf[i] = LONG_MIN;
		savedi[i] = LONG_MIN;
	}

	/* Set top of register save area, relative to fp. */
	savedtop = -framesize;

	lfs_set = 0;  /* empty set */
}

/* Mark a register as being saved. */

regsave(const char* regname, long offset, int size)
{
	int regnum = atoi(regname + 1);

	assert(regnum >= 0 && regnum <= 31);
	switch (regname[0]) {
		case 'f':
			savedf[regnum] = offset;
			framesize += 8;
			if (size == 4)
				lfs_set |= ((uint32_t)1<<regnum);
			break;
		case 'r':
			savedi[regnum] = offset;
			framesize += 4;
			break;
	}
}

static void
saveloadregs(const char* ops, const char* opm, const char *opf)
{
	long offset = savedtop;
	int reg;

	/* Do floating-point registers. */
	for (reg = 31; reg >= 0; reg--) {
		if (savedf[reg] != LONG_MIN) {
			offset -= 8;
			fprintf(codefile, "%s f%d, %ld(fp)\n",
				opf, reg, offset);
		}
	}

	if (savedi[31] != LONG_MIN && savedi[30] != LONG_MIN) {
		/*
		 * Do multiple registers from reg to r31.
		 *
		 * Using stmw or lmw reduces code size, but in some
		 * processors, runs slower than the equivalent pile of
		 * stw or lwz instructions.
		 */
		reg = 30;
		while (reg > 0 && savedi[reg - 1] != LONG_MIN)
			reg--;
		offset -= (32 - reg) * 4;
		fprintf(codefile, "%s r%d, %ld(fp)\n", opm, reg, offset);
	} else
		reg = 32;

	/* Do single general-purpose registers. */
	for (reg--; reg >= 0; reg--) {
		if (savedi[reg] != LONG_MIN) {
			offset -= 4;
			fprintf(codefile, "%s r%d, %ld(fp)\n",
				ops, reg, offset);
		}
	}
}

f_regsave(void)
{
	int reg;

	emit_prolog();
	saveloadregs("stw", "stmw", "stfd");

	/*
	 * Register variables with offset >= 0 must load an argument
	 * from that offset.
	 */
	for (reg = 31; reg >= 0; reg--)
		if (savedf[reg] >= 0)
			fprintf(codefile, "%s f%d, %ld(fp)\n",
				(lfs_set & ((uint32_t)1<<reg)) ? "lfs" : "lfd",
				reg, savedf[reg]);

	for (reg = 31; reg >= 0; reg--)
		if (savedi[reg] >= 0)
			fprintf(codefile, "lwz r%d, %ld(fp)\n",
				reg, savedi[reg]);
}

/* Restore all saved registers. */

regreturn(void)
{
	saveloadregs("lwz", "lmw", "lfd");
}

#endif
