/* $Header$ */
/* IDENTIFIER DESCRIPTOR */

#include "nopp.h"

/*	Since the % operation in the calculation of the hash function
	turns out to be expensive, it is replaced by the cheaper XOR (^).
	Each character of the identifier is xored with an 8-bit mask which
	depends on the position of the character; the sum of these results
	is the hash value.  The random masks are obtained from a
	congruence generator in idf.c.
*/

#define	HASHSIZE	256	/* must be a power of 2 */
#define	HASH_X		0253	/* Knuth's X */
#define	HASH_A		77	/* Knuth's a */
#define	HASH_C		153	/* Knuth's c */

extern char hmask[];		/* the random masks */
#define	HASHMASK		(HASHSIZE-1)	/* since it is a power of 2 */
#define	STARTHASH()		(0)
#define	ENHASH(hs,ch,ps)	(hs + (ch ^ hmask[ps]))
#define	STOPHASH(hs)		(hs & HASHMASK)

struct idstack_item	{	/* stack of identifiers */
	struct idstack_item *next;
	struct idf *is_idf;
};


/* allocation definitions of struct idstack_item */
/* ALLOCDEF "idstack_item" */
extern char *st_alloc();
extern struct idstack_item *h_idstack_item;
#define	new_idstack_item() ((struct idstack_item *) \
		st_alloc((char **)&h_idstack_item, sizeof(struct idstack_item)))
#define	free_idstack_item(p) st_free(p, h_idstack_item, sizeof(struct idstack_item))


struct idf	{
	struct idf *next;
	char *id_text;
#ifndef NOPP
	struct macro *id_macro;
	int id_resmac;		/* if nonzero: keyword of macroproc. 	*/
#endif NOPP
	int id_reserved;	/* non-zero for reserved words		*/
	struct def *id_def;	/* variables, typedefs, enum-constants	*/
	struct sdef *id_sdef;	/* selector tags			*/
	struct tag *id_struct;	/* struct and union tags		*/
	struct tag *id_enum;	/* enum tags				*/
	int id_special;		/* special action needed at occurrence	*/
};


/* allocation definitions of struct idf */
/* ALLOCDEF "idf" */
extern char *st_alloc();
extern struct idf *h_idf;
#define	new_idf() ((struct idf *) \
		st_alloc((char **)&h_idf, sizeof(struct idf)))
#define	free_idf(p) st_free(p, h_idf, sizeof(struct idf))


extern struct idf *str2idf(), *idf_hashed();

extern int level;
extern struct idf *gen_idf();