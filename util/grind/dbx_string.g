/* $Header$
   Grammar of a string of a debugger symbol table entry.
*/

{
#include	<out.h>
#include	<alloc.h>

#include	"type.h"
#include	"symbol.h"
#include	"scope.h"
#include	"class.h"
#include	"idf.h"

extern char	*strindex();
extern long	str2long();
extern double	atof();
extern int	saw_code;
extern long	pointer_size;

static char	*DbxPtr;		/* current pointer in DBX string */
static int	AllowName;		/* set if NAME legal at this point */
static long	ival;
static double	fval;
static char	*strval;
static int	last_index[2];
static struct outname	*currnam;

static struct literal *get_literal_space();
static struct fields *get_field_space();
static end_field();
static char *string_val();
}

%start DbxParser, debugger_string;

%prefix DBS;

%lexical DBSlex;

%onerror DBSonerror;

%token	INTEGER, REAL, STRING, NAME;

debugger_string
  { register p_symbol s;
    char *str;
    p_type tmp = 0;
  }
:
  name(&str)
  [ /* constant name */
			{ s = NewSymbol(str, CurrentScope, CONST, currnam); }
	'c' const_name(s)

  | /* type name */
			{ s = NewSymbol(str, CurrentScope, TYPE, currnam); }
	't' type_name(&(s->sy_type))
			{ if (! s->sy_type->ty_sym) s->sy_type->ty_sym = s; }

  | /* tag name (only C?) */
			{ s = NewSymbol(str, CurrentScope, TAG, currnam); }
	'T' tag_name(s)

  | /* end scope */
	'E' INTEGER
			{ close_scope(); }

  | /* module begin */
			{ s = NewSymbol(str, CurrentScope, MODULE, currnam); }
	'M' INTEGER
			{ open_scope(s, 1);
			  s->sy_name.nm_scope = CurrentScope;
			  CurrentScope->sc_start = currnam->on_valu;
			  CurrentScope->sc_proclevel = currnam->on_desc;
			  add_scope_addr(CurrentScope);
			}

  | /* external procedure */
			{ s = NewSymbol(str, FileScope, PROC, currnam); }
	'P' routine(s)

  | /* private procedure */
			{ s = NewSymbol(str, CurrentScope, PROC, currnam); }
	'Q' routine(s)

  | /* external function */
			{ s = NewSymbol(str, FileScope, FUNCTION, currnam); }
	'F' function(s)

  | /* private function */
			{ s = NewSymbol(str, CurrentScope, FUNCTION, currnam); }
	'f' function(s)

  | /* global variable, external */
				/* maybe we already know it; but we need
				   the type information anyway for other
				   types.
				*/
			{ s = Lookup(findidf(str), FileScope, VAR);
			  if (s) {
				tmp = s->sy_type;
			  } else s = NewSymbol(str, FileScope, VAR, currnam);
			}
	'G' type(&(s->sy_type), (int *) 0)
			{ if (tmp) s->sy_type = tmp; } 

  | /* static variable */
			{ s = NewSymbol(str, CurrentScope, VAR, currnam); }
	'S' type(&(s->sy_type), (int *) 0)

  | /* static variable, local scope */
			{ s = NewSymbol(str, CurrentScope, VAR, currnam); }
	'V' type(&(s->sy_type), (int *) 0)

  | /* register variable */
			{ s = NewSymbol(str, CurrentScope, REGVAR, currnam); }
	'r' type(&(s->sy_type), (int *) 0)

  | /* value parameter */
			{ s = NewSymbol(str, CurrentScope, LOCVAR, currnam); }
	'p' type(&(s->sy_type), (int *) 0)
			{ add_param_type('p', s); }

  | /* value parameter but address passed */
			{ s = NewSymbol(str, CurrentScope, VARPAR, currnam); }
	'i' type(&(s->sy_type), (int *) 0)
			{ add_param_type('i', s); }

  | /* variable parameter */
			{ s = NewSymbol(str, CurrentScope, VARPAR, currnam); }
	'v' type(&(s->sy_type), (int *) 0)
			{ add_param_type('v', s); }

  | /* local variable */
			{ s = NewSymbol(str, CurrentScope, LOCVAR, currnam); }
	type_name(&(s->sy_type))

  | /* function result in Pascal; ignore ??? */
			{ s = NewSymbol(str, CurrentScope, LOCVAR, currnam); }
	'X' type_name(&(s->sy_type))
  ]
  ';'?
;

name(char **s;)
:
  /* anything up to a ':' */
  NAME	{ *s = strval; }
;

const_name(p_symbol cst;)
  { int type_index[2];
    long iconst;
    register char *p;
  }
:
  '='
  [
/*
	'b' integer_const(&(cst->sy_const.co_ival))	/* boolean */
/*  |
*/
	'c' integer_const(&(cst->sy_const.co_ival))	/* character */
				{ cst->sy_type = char_type; }
  |
	'i' integer_const(&(cst->sy_const.co_ival))	/* integer */
				{ cst->sy_type = long_type; }
  |
  	'r' real_const(&(cst->sy_const.co_rval))	/* real */
				{ cst->sy_type = double_type; }
  |
	's' string_const				/* string */
				{ cst->sy_const.co_sval = string_val(strval);
				  cst->sy_type = string_type;
				}
  |
	'e' type_index(type_index) ',' integer_const(&(cst->sy_const.co_ival))
				/* enumeration constant;
				 * enumeration type, value
				 */
				{ cst->sy_type = *tp_lookup(type_index); }
				
  |
	'S' type_index(type_index)
				{ cst->sy_type = *tp_lookup(type_index);
				  cst->sy_const.co_setval = p =
				    Malloc((unsigned) cst->sy_type->ty_size);
				}
	[ ',' integer_const(&iconst)
				{ *p++ = iconst; }
	]+
				/* set constant:
				 *  settype, values of the bytes
				 *  in the set.
				 */
  ]
;

integer_const(long *iconst;)
  { int sign = 0; }
:
  [ '+' | '-' { sign = 1; } ]?
  INTEGER			{ *iconst = sign ? -ival : ival; }
;

real_const(double *f;)
  { int sign = 0; }
:
  [ '+' | '-' { sign = 1; } ]?
  REAL				{ *f = sign ? fval : -fval; }
;

string_const
:
  STRING			/* has SINGLE quotes! */
;

type_name(p_type *t;)
  { int type_index[2]; p_type *p; }
:
  type_index(type_index)
  [
	'='			
	type(t, type_index)
				{ p = tp_lookup(type_index);
				  if (*p && *p != incomplete_type) {
					if (!((*p)->ty_flags & T_CROSS))
						error("Redefining (%d,%d) %d",
						  type_index[0],
						  type_index[1],
						  (*p)->ty_class);
					if (*t && *p != *t) free_type(*p);
				  }
				  if (*t) *p = *t; 
				}
  |
				{ p = tp_lookup(type_index); }
  ]
				{ if (*p == 0) *p = incomplete_type;
				  *t = *p;
				}
;

type_index(int *type_index;)
:
[
  INTEGER			{ type_index[0] = 0; type_index[1] = ival; }
|
  '(' INTEGER			{ type_index[0] = ival; }
  ',' INTEGER			{ type_index[1] = ival; }
  ')'
]
				{ last_index[0] = type_index[0];
				  last_index[1] = type_index[1];
				}
;

tag_name(p_symbol t;)
  { int type_index[2]; p_type *p; }
:
  type_index(type_index)
  '='				
  type(&(t->sy_type), type_index)
				{ p = tp_lookup(type_index);
				  if (*p && *p != incomplete_type) {
					if (!((*p)->ty_flags & T_CROSS))
						error("Redefining (%d,%d) %d",
						  type_index[0],
						  type_index[1],
						  (*p)->ty_class);
					if (t->sy_type && *p != t->sy_type) {
						free_type(*p);
					}
				  }
				  if (t->sy_type) *p = t->sy_type; 
				  if (*p == 0) *p = incomplete_type;
				}
;

function(p_symbol p;)
:
  			{ p->sy_type = new_type();
			  p->sy_type->ty_class = T_PROCEDURE;
			  p->sy_type->ty_size = pointer_size;
			}
  type(&(p->sy_type->ty_retval), (int *) 0) 
  			{ if (CurrentScope != FileScope &&
			      saw_code) {
				/* if saw_code is not set, it is a nested
				   procedure
				*/
				close_scope();
			  }
			  saw_code = 0;
			  open_scope(p, 1);
			  p->sy_name.nm_scope = CurrentScope;
			  CurrentScope->sc_start = currnam->on_valu;
			  add_scope_addr(CurrentScope);
			  CurrentScope->sc_proclevel = currnam->on_desc;
			}
;

routine(p_symbol p;)
:
  			{ p->sy_type = new_type();
			  p->sy_type->ty_class = T_PROCEDURE;
			  p->sy_type->ty_size = pointer_size;
			  if (CurrentScope != FileScope &&
			      saw_code) {
				/* if saw_code is not set, it is a nested
				   procedure
				*/
				close_scope();
			  }
			  saw_code = 0;
			  open_scope(p, 1);
			  p->sy_name.nm_scope = CurrentScope;
			  CurrentScope->sc_start = currnam->on_valu;
			  add_scope_addr(CurrentScope);
			  CurrentScope->sc_proclevel = currnam->on_desc;
			}
  INTEGER ';'
  type(&(p->sy_type->ty_retval), (int *) 0) 
;

type(p_type *ptp; int *type_index;)
  { register p_type tp = 0;
    p_type t1, t2;
    long ic1, ic2;
    int A_used = 0;
  }
:			{ *ptp = 0; }
  [
	/* type cross reference */
	/* these are used in C for references to a struct, union or
	 * enum that has not been declared (yet)
	 */
  	'x'		{ tp = new_type(); tp->ty_flags = T_CROSS; }
  	[ 's'	/* struct */
			{ tp->ty_class = T_STRUCT; }
  	| 'u'	/* union */
			{ tp->ty_class = T_UNION; }
  	| 'e'	/* enum */
			{ tp->ty_class = T_ENUM; }
  	]
			{ AllowName = 1; }
  	name(&(tp->ty_tag))
  |
  	/* subrange */
  	/* the integer_const's represent the lower and the upper bound.
   	 * A subrange type defined as subrange of itself is an integer type.
   	 * If the second integer_const == 0, but the first is not, we
   	 * have a floating point type with size equal to the first
   	 * integer_const.
   	 * Upperbound -1 means unsigned int or unsigned long.
   	 */
  	'r' type_name(&t1) ';'
	[ 'A' integer_const(&ic1)	{ A_used = 1; }
	| integer_const(&ic1)
	]
	';'
	[ 'A' integer_const(&ic2)	{ A_used |= 2; }
	| integer_const(&ic2)
	]
			{ *ptp = subrange_type(A_used,
					       last_index,
					       ic1,
					       ic2,
					       type_index);
			}
  |
  	/* array; first type is bound type, next type
   	 * is element type
   	 */
  	'a' type(&t1, (int *) 0) ';' type(&t2, (int *) 0)
			{ *ptp = array_type(t1, t2); }
  |
  	/* structure type */
  	's'		{ tp = new_type(); tp->ty_class = T_STRUCT; }
	structure_type(tp)
  |
  	/* union type */
  	'u'		{ tp = new_type(); tp->ty_class = T_UNION; }
	structure_type(tp)
  |
  	/* enumeration type */
  	'e'		{ tp = new_type(); tp->ty_class = T_ENUM; }
	enum_type(tp)
  |
  	/* pointer type */
  	'*'		{ tp = new_type(); tp->ty_class =T_POINTER;
			  tp->ty_size = pointer_size;
			}
  	type(&(tp->ty_ptrto), (int *) 0)
  |
  	/* function type */
  	'f'		{ tp = new_type(); tp->ty_class = T_PROCEDURE;
			  tp->ty_size = pointer_size;
			}
  	type(&(tp->ty_retval), (int *) 0) 
/*
  	[ %prefer
		',' param_list(tp)
  	|
  	]
*/
  |
  	/* procedure type */
  	'Q'		{ tp = new_type(); tp->ty_class = T_PROCEDURE;
			  tp->ty_size = pointer_size;
			}
  	type(&(tp->ty_retval), (int *) 0) 
	',' param_list(tp)
  |
  	/* another procedure type */
  	'p'		{ tp = new_type(); tp->ty_class = T_PROCEDURE;
			  tp->ty_size = pointer_size;
			  tp->ty_retval = void_type;
			}
	param_list(tp)
  |
  	/* set type */
  	/* the first integer_const represents the size in bytes,
   	 * the second one represents the low bound
   	 */
  	'S'		{ tp = new_type(); tp->ty_class = T_SET; }
	type(&(tp->ty_setbase), (int *) 0) ';'
	[
		integer_const(&(tp->ty_size)) ';'
		integer_const(&(tp->ty_setlow)) ';'
	|
			{ set_bounds(tp); }
	]
  |
	/* file type of Pascal */
	'L'		{ tp = new_type(); tp->ty_class = T_FILE; }
	type(&(tp->ty_fileof), (int *) 0)
  |
  	type_name(ptp)
			{ if (type_index &&
			      *ptp == incomplete_type &&
			      type_index[0] == last_index[0] &&
			      type_index[1] == last_index[1]) {
				*ptp = void_type;
			  }
			}
  ]
			{ if (! *ptp) *ptp = tp; }
;

structure_type(register p_type tp;)
  { register struct fields *fldp;
    register p_symbol s;
  }
:
  integer_const(&(tp->ty_size))		/* size in bytes */
			{ open_scope((p_symbol) 0, 0); }
  [			{ fldp = get_field_space(tp); }
	name(&(fldp->fld_name))
			{ s = NewSymbol(fldp->fld_name, CurrentScope, FIELD, currnam);
			  s->sy_field = fldp;
			}
	type(&(fldp->fld_type), (int *) 0) ','
	integer_const(&(fldp->fld_pos)) ','	/* offset in bits */
	integer_const(&(fldp->fld_bitsize)) ';'	/* size in bits */
  ]*
  ';'			{ end_field(tp); 
			  close_scope();
			}
;

enum_type(register p_type tp;)
  { register struct literal *litp;
    long maxval = 0;
    register p_symbol s;
  }
:
  [			{ litp = get_literal_space(tp); }
	name(&(litp->lit_name))
	integer_const(&(litp->lit_val)) ',' 
			{ if (maxval < litp->lit_val) maxval = litp->lit_val;
			  AllowName = 1;
			  s = NewSymbol(litp->lit_name, CurrentScope, CONST, (struct outname *) 0);
			  s->sy_const.co_ival = litp->lit_val;
			  s->sy_type = tp;
			}
  ]*
  ';'			{ end_literal(tp, maxval); }
;

param_list(p_type t;)
  { register struct param *p;
    long iconst;
  }
:
  integer_const(&iconst) ';'	/* number of parameters */
			{ t->ty_nparams = iconst;
			  t->ty_params = p = (struct param *)
			    Malloc((unsigned)(t->ty_nparams * sizeof(struct param)));
			}
  [
  	[	'p'	{ p->par_kind = 'p'; }
  	|	'v'	{ p->par_kind = 'v'; }
  	|	'i' 	{ p->par_kind = 'i'; }
  	]
  	type(&(p->par_type), (int *) 0) ';'
			{ t->ty_nbparams += 
				param_size(p->par_type, p->par_kind);
			  p++;
			}
  ]*
;

{
static char *dbx_string;
static char *DbxOldPtr;

struct outname *
DbxString(n)
  struct outname	*n;
{
  currnam = n;
  DbxPtr = n->on_mptr;
  dbx_string = DbxPtr;
  AllowName = 1;
  DbxParser();
  return currnam;
}

/*ARGSUSED*/
DBSmessage(n)
{
  fatal("error in Dbx string \"%s\", DbxPtr = \"%s\", DbxOldPtr = \"%s\"",
	dbx_string,
	DbxPtr,
	DbxOldPtr);

}

DBSonerror(tk, p)
  int	*p;
{
  DbxPtr = DbxOldPtr;
/* ???  if (DBSsymb < 0) {
	while (*p && *p != ';') p++;
	if (*p) DbxPtr = ";";
	return;
  }
*/
  if (! tk) {
	while (*p && *p != NAME) p++;
	if (*p) {
		AllowName = 1;
	}
  }
  else if (tk == NAME) AllowName = 1;
}

DBSlex()
{
  register char *cp = DbxPtr;
  int allow_name = AllowName;
  register int c;

  AllowName = 0;
  DbxOldPtr = cp;
  c = *cp;
  if (c == '\\' && *(cp+1) == '\0') {
	currnam++;
	cp = currnam->on_mptr;
	DbxOldPtr = cp;
	c = *cp;
  }
  if (! c) {
	DbxPtr = cp;
	return -1;
  }
  if ((! allow_name && is_token(c)) || c == ';') {
	DbxPtr = cp+1;
	return c;
  }
  if (is_dig(c)) {
	int retval = INTEGER;

	while (++cp, is_dig(*cp)) /* nothing */;
	c = *cp;
	if (c == '.') {
		retval = REAL;
		while (++cp, is_dig(*cp)) /* nothing */;
		c = *cp;
	}
	if (c == 'e' || c == 'E') {
		char *oldcp = cp;

		cp++;
		c = *cp;
		if (c == '-' || c == '+') {
			cp++;
			c = *cp;
		}
		if (is_dig(c)) {
			retval = REAL;
			while (++cp, is_dig(*cp)) /* nothing */;
		}
		else cp = oldcp;
	}
	c = *cp;
	*cp = 0;
	if (retval == INTEGER) {
		ival = str2long(DbxOldPtr, 10);
	}
	else {
		fval = atof(DbxOldPtr);
	}
	*cp = c;
	DbxPtr = cp;
	return retval;
  }
  if (c == '\'') {
	cp++;
	strval = cp;
	while ((c = *cp) && c != '\'') {
		if (c == '\\') cp++;	/* backslash escapes next character */
		if (!(c =  *cp)) break;	/* but not a null byte */
		cp++;
	}
	if (! c) DBSmessage(0);	/* no return */
	*cp = 0;
	DbxPtr = cp + 1;
	return STRING;
  }
  strval = cp;
  while ((c = *cp) && c != ':' && c != ',') cp++;
  DbxPtr = *cp ? cp+1 : cp;
  *cp = 0;
  return NAME;
}

static struct fields *
get_field_space(tp)
  register p_type tp;
{
  if (! (tp->ty_nfields & 07)) {
	tp->ty_fields = (struct fields *)
		  Realloc((char *) tp->ty_fields,
			    (tp->ty_nfields+8)*sizeof(struct fields));
  }
  return &tp->ty_fields[tp->ty_nfields++];
}

static
end_field(tp)
  register p_type tp;
{
  tp->ty_fields = (struct fields *)
	Realloc((char *) tp->ty_fields,
		tp->ty_nfields * sizeof(struct fields));
}

static struct literal *
get_literal_space(tp)
  register p_type tp;
{
  if (! (tp->ty_nenums & 07)) {
	tp->ty_literals = (struct literal *)
		Realloc((char *) tp->ty_literals,
			(tp->ty_nenums+8)*sizeof(struct literal));
  }
  return &tp->ty_literals[tp->ty_nenums++];
}

static char *
string_val(s)
  char	*s;
{
  register char *ns = s, *os = s;
  register unsigned int i = 1;

  for (;;) {
	if (!*os) break;
	i++;
	if (*os == '\\') {
		os++;
		*ns++ = *os++;
	}
	else *ns++ = *os++;
  }
  *ns = '\0';
  return Salloc(s, i);
}

}