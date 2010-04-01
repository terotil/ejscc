/* Copyleft 2002, Tero Tilus <tero@tilus.net>
 *
 * $Id: ejsc_parser.y,v 1.8 2002/07/09 14:11:39 terotil Exp $
 *
 * This file is part of ejscc, a program to compile Extended Java
 * Sketchpad Constructions to ordinary syntax.
 *
 * Ejscc is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.  
 * 
 * Ejscc is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.  
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
 * USA 
 */
%token <v.value.s> NAME 
%token <v.value.s> STRING 
%token <v.value.s> COMMENT
%token <v.value.i> INT
%token <v.value.f> FLOAT
%token BEGIN_BLOCK END_BLOCK
%{
#define MAXVARS 16
#define MAXARGLISTS 8
#define MAXSYMS 300
  /* Keep up with linenumbers */
  int yylineno=1;

  /* Index constructions to generate evalIds */
  int evalIndex=0;

  /* Error "handling" */
  int yyerror(char *s) {
    fprintf(stderr, "%s\n", s);
    fflush(stderr);
    return 0;
  }
  
  /* Get first non-null index in tVariable array */
  int first_null_index(tVariable *vp) {
    int i;
    for (i=0 ; i<MAXVARS; i++) {
      /* Variable arrays are initially filled with null-variables, so
	 first free index is first index having null-variable */
      if ( vp[i].type == tNull ) {
	return i;
      }
    }
    return MAXVARS;
  }
  /* The same as abow, but for array of arrays */
  int first_null_index_(tVariable **vpp) {
    int i;
    /* Array of variable arrays is initially filled with
       null-pointers. */
    for (i=0 ; i<MAXVARS; i++) {
      if ( vpp[i] == NULL ) {
	return i;
      }
    }
    return MAXVARS;
  }

  /* Get the index of symbol named name, -1 if name doesn't exist in
     symbol table of given symbol sym */
  int get_sym_index(tSymbol *sym, tIdentifier name) {
    int i;
    if ((*sym).symTable == NULL ||
	(*sym).symTSize < 1) {
      /* No symbol table */
      return -1;
    }
    /* Browse symbol table */
    for (i=0; (*sym).symTable[i]!=NULL; i++) {
      /* Compare symbol name and given identifier */
      if ( strcmp((*(*sym).symTable[i]).symName, name) == 0 ) {
	return i;
      }
    }
    /* Symbol not found */
    return -1;
  }

  /* Assure free space in symTable of given symbol, return first free
     index */
  int check_symtable(tSymbol *sym) {
    int i, newsize;
    if ( ((*sym).symTable == NULL) ||
	 ((*sym).symTSize < 1) ) {
      /* Initialize symbol table */
#ifdef EJSCCDEBUG
      if ( ejsccdebug ) {
	printf("ejsccdebug: Init symtable of '%s' (%d).\n", (*sym).symName, (int)sym);
	fflush(stdout);
      }
#endif
      newsize = MAXSYMS;
      (*sym).symTable = (tSymbol **)malloc(newsize * sizeof(tSymbol *));
      /* Fill with NULL */
      for (i=0; i<newsize; (*sym).symTable[i++] = NULL );
      (*sym).symTSize = newsize;
    } else {
      /* Check free space */
      if ( (*sym).symTable[(*sym).symTSize-1] != NULL ) {
	/* Full, must realloc */
	/* Reallocation can't be allowed due direct references to symbols */
	fprintf(outfile, "Fatal error: Too many symbols in '%s'.\n", (*sym).symName);
	exit(1);
	/*
#ifdef EJSCCDEBUG
	if ( ejsccdebug ) {
	  printf("ejsccdebug: Realloc symtable of '%s'.\n", (*sym).symName);
	  fflush(stdout);
	}
#endif
	newsize = ((*sym).symTSize+10) * sizeof(tSymbol);
	(*sym).symTable = realloc((*sym).symTable, newsize);
	for (i=(*sym).symTSize; i<(*sym).symTSize+10; 
	     (*sym).symTable[i++] = nullSym);
	(*sym).symTSize += 10;
	*/
      } 
    }
    /* Find first free (NULL or nullSym) index */
    for (i=0; i<(*sym).symTSize; i++) {
      if ( ((*sym).symTable[i] == NULL) ||
	   ((*((*sym).symTable[i])).symName == nullSym.symName) ) {
	return i;
      }
    }
    /* symTable full.  Shouldn't ever happen */
    yyerror("symTable still full after assuring free space.  Fatal error."); 
    exit(1);
  }


  int append_symbol_to_symtable(tIdentifier name, tVariable *val, tSymbol *sym) {
    /* Check if symbol already exists. */
    int i = get_sym_index(sym, name);
    if ( i<0 ) {
      /* New symbol */
      i = check_symtable(sym);
      if ( i<0 ) return -1;
      if ( (*sym).symTable[i] == NULL ) {
	(*sym).symTable[i] = (tSymbol *)malloc(sizeof(tSymbol));
	(*(*sym).symTable[i]) = nullSym;
#ifdef EJSCCDEBUG
	if ( ejsccdebug ) {
	  printf("ejsccdebug: Created new symbol '%s'. (%d)\n", 
		 name, (int)(*sym).symTable[i]);
	  fflush(stdout);
	}
#endif
      }
      (*(*sym).symTable[i]).symName = name;
      (*(*sym).symTable[i]).symIndex = 0;
      // No need to reset previously set defaults
      // (*(*sym).symTable[i]).symTSize = 0;
      // (*(*sym).symTable[i]).symTable = NULL;
      (*(*sym).symTable[i]).parentSym = sym;
      (*(*sym).symTable[i]).beingCompiled = false;
    }
    /* Set value of symbol */
    (*(*sym).symTable[i]).symValue = val;
#ifdef EJSCCDEBUG
    if ( ejsccdebug ) {
      printf("ejsccdebug: Set val of sym '%s' in symTable[%d] of '%s'. (%d, %d)\n", 
	     name, i, (*sym).symName, (int)(*sym).symTable[i], (int)sym);
      fflush(stdout);
    }
#endif
    return i;
  }

  /* Append simple (object, constant, etc.) symbol to symbol table of
     current symbol */
  int append_symbol_to_current(tIdentifier name, tVariable *val) {
    return append_symbol_to_symtable(name, val, currentSym);
  }

  /* Generate human readable 'name' of given variable */
  char *get_name(tVariable *var) {
    char *tmp;
    switch ( (*var).type ) {
    case tOb:
      tmp = (char*)malloc((16 + strlen((*var).value.o.objName))*sizeof(char));
      sprintf(tmp, "construction '%s'", (*var).value.o.objName);
      return tmp;
    case tSt:
      return "string";
    case tIn:
      return "integer";
    case tFl:
      return "float";
    case tId:
      return "identifier";
    case tNull:
      return "null";
    default:
      return "#UNKNOWN#";
    }
  }

  void set_scope(tSymbol *sym) {
    tVariable *val;
    int i, j;
    val = (*sym).symValue;
    /* Set scope of construction objects given as argument */
    if ( (*val).value.o.arguments != NULL ) {
      i=0;
      while ( (*val).value.o.arguments[i] != NULL ) {
	j=0;
	while ((*val).value.o.arguments[i][j].type != tNull) {
	  (*val).scope = sym;
	  j++;
	}
	i++;
      }
    }
  }

%}

%union {
  tBoolean b;
  tSymbol s;
  tVariable v;
  tVariable *vp;
  tVariable **vpp;
}

%nonassoc NAME '\n' COMMENT
%nonassoc CONS_
%nonassoc COBJ_ATTR
%nonassoc COBJ_CONS
%nonassoc '='
%%

construction:
  construction construction %prec CONS_
  | construction_object maybecomment ';' %prec COBJ_CONS { 
    tIdentifier name;
    int i;
    static int cnum=1; /* Number of construction */
    static int lastlineno=0; /* Line number when last time visiting */
    /* Generate unique name */
    if ( yylineno != lastlineno ) {
      cnum = 1;
      lastlineno = yylineno;
    }
    name = (tIdentifier)malloc(32*sizeof(char));
    sprintf(name, "line_%d_construction_%d", yylineno, cnum++);
    i = append_symbol_to_current(name, $<vp>1);
    (*($<vp>1)).scope = (*currentSym).symTable[i];
    /* In case of function definition, fix name */
    if ( ((*((*currentSym).symTable[i])).symTSize != 0) &&
	 ((*(*((*currentSym).symTable[i])).symValue).type == tOb) ) {
      //      free((*currentSym).symTable[i].symName);
      (*((*currentSym).symTable[i])).symName = 
	(*(*((*currentSym).symTable[i])).symValue).value.o.objName;
    }
#ifdef EJSCCDEBUG
    if ( ejsccdebug ) {
      printf("ejsccdebug: Assigned to '%s'.\n", name);
      fflush(stdout);
    }
#endif
}
  | NAME '=' attribute ';' {
    int i;
    i = append_symbol_to_current($<v.value.s>1, $<vp>3);
    (*($<vp>3)).scope = (*currentSym).symTable[i];
#ifdef EJSCCDEBUG
    if ( ejsccdebug ) {
      printf("ejsccdebug: Assigned to '%s'.\n", $<v.value.s>1);
      fflush(stdout);
    }
#endif
  } 
  | COMMENT
  ;

maybecomment:
  COMMENT
  |
  ;

construction_object:
  NAME attributes formats codeblock { 
    tVariable *val;
    int ***tmp_eval;
    int i,j,k;
    /* Allocate memory */
    val = (tVariable *)malloc(sizeof(tVariable));
    /* Create construction object */
    (*val).type = tOb;
    (*val).evalId = evalIndex; evalIndex += EVALIDSTEP; // Unique id
    (*val).value.o.objName = $<v.value.s>1; // Name
    /* Allocate memory for return values and reset them */
    (*val).value.o.returnValues = (char **)malloc(MAXSYMS * sizeof(char *));
    memset((*val).value.o.returnValues, (int)NULL, MAXSYMS * sizeof(char *));
    /* Decide type.  Existing codeblock means definition */
    if ( $<b>4 == true ) {
      (*val).value.o.type = Definition;
    } else {
      (*val).value.o.type = Object;
    }
    /* Evaluation id's to keep track on the need of re-evaluation of arguments */
    (*val).value.o.arguments = $<vpp>2; /* Argument list */
    tmp_eval = (*val).value.o.argumentEvalId = (int ***)malloc(MAXARGLISTS * sizeof(int **));
    for ( i=0 ; i<MAXARGLISTS ; i++ ) {
      tmp_eval[i] = (int **)malloc(MAXVARS * sizeof(int *));
      for ( j=0 ; j<MAXVARS ; j++ ) {
	tmp_eval[i][j] = (int *)malloc(MAXSYMS * sizeof(int));
	for ( k=0 ; k<MAXSYMS ; tmp_eval[i][j][k++] = -1 );
      }
    }
    /* Evaluation id's to keep track on the need of re-evaluation of formats */
    (*val).value.o.formats = $<vp>3; /* Format list */
    (*tmp_eval) = (*val).value.o.formatEvalId = (int **)malloc(MAXARGLISTS * sizeof(int *));
    for ( i=0 ; i<MAXARGLISTS ; i++ ) {
      (*tmp_eval)[i] = (int *)malloc(MAXSYMS * sizeof(int));
      for ( j=0 ; j<MAXSYMS ; (*tmp_eval)[i][j++] = -1 );
    }
    (*val).scope = currentSym;
    $<vp>$ = val;
#ifdef EJSCCDEBUG
    if ( ejsccdebug ) {
      printf("ejsccdebug: Found %s.\n", get_name(val));
      fflush(stdout);
    }
#endif
  }
  ;

attributes:
  attributes '(' attributelist ')' {
    int i = first_null_index_($<vpp>1);
#ifdef EJSCCDEBUG
    if ( ejsccdebug ) {
      printf("ejsccdebug: Yet another argument list found.\n");
      fflush(stdout);
    }
#endif
    if ( i > MAXARGLISTS-1 ) {
      /* FIXME: realloc */
      yyerror("Error. Too many attributelists.\n");
    } else {
      $<vpp>$ = $<vpp>1;
      $<vpp>$[i] = $<vp>3;
    }
  }
  | '(' attributelist ')' {
    int size = MAXARGLISTS;
    int i;
#ifdef EJSCCDEBUG
    if ( ejsccdebug ) {
      printf("ejsccdebug: Argument list found.\n");
      fflush(stdout);
    }
#endif
    $<vpp>$ = (tVariable **)malloc(size * sizeof(tVariable *)); 
    for (i=0 ; i<size; $<vpp>$[i++]=NULL);
    $<vpp>$[0] = $<vp>2;
  }
  ;

attributelist:
  attributelist ',' attribute {
    int i = first_null_index($<vp>1);
    if ( i > MAXVARS-1 ) { 
      /* FIXME: realloc */
      yyerror("Error. Too many attributes.\n"); 
    } else {
      $<vp>$ = $<vp>1;
      $<vp>$[i] = (*($<vp>3));
    }
  }
  | attribute { 
    int size = MAXVARS;
    int i;
    $<vp>$ = (tVariable *)malloc(size * sizeof(tVariable)); 
    /* Set all variables to 'nullVar' */
    for (i=0 ; i<size; $<vp>$[i++]=nullVar);
    $<vp>$[0] = (*($<vp>1));
  }
  | { $<vp>$ = NULL; }
  ;

attribute:
  maybecomment simple_attribute maybecomment { $<vp>$ = $<vp>2; }
  | maybecomment construction_object maybecomment %prec COBJ_ATTR { 
    $<vp>$ = $<vp>2; 
} 
  ;

simple_attribute:
  number { 
    $<vp>$ = (tVariable*)malloc(sizeof(tVariable)); 
    (*($<vp>$)) = $<v>1;
  }
  | STRING { 
    $<vp>$ = (tVariable*)malloc(sizeof(tVariable)); 
    (*($<vp>$)) = $<v>1;
}
  | NAME { 
    $<vp>$ = (tVariable*)malloc(sizeof(tVariable)); 
    (*($<vp>$)) = $<v>1;
}
  

formats:
  '[' formatlist ']' { 
#ifdef EJSCCDEBUG
    if ( ejsccdebug ) {
      printf("ejsccdebug: Format list found.\n");
      fflush(stdout);
    }
#endif
    $<vp>$ = $<vp>2; 
}
  | { $<vp>$ = NULL; }
  ;

formatlist:
  formatlist ',' format {
    int i = first_null_index($<vp>1);
    if ( i > MAXVARS-1 ) { 
      /* FIXME: realloc */
      fprintf(stderr, "Fatal error: Too many formats on line %d.\n", yylineno); 
      exit(1);
    } else {
      $<vp>$ = $<vp>1;
      $<vp>$[i] = (*($<vp>3));
    }
  }
  | format { 
    int size = MAXVARS;
    int i;
    $<vp>$ = (tVariable *)malloc(size * sizeof(tVariable)); 
    /* Set all variables to 'nullVar' */
    for (i=0 ; i<size; $<vp>$[i++]=nullVar);
    $<vp>$[0] = (*($<vp>1));
  }
  ;

format:
  maybecomment simple_attribute maybecomment { $<vp>$ = $<vp>2; }
  | maybecomment format_call maybecomment {
    /*
    $<vp>$ = (tVariable*)malloc(sizeof(tVariable)); 
    (*($<vp>$)) = $<v>2; 
    */
    $<vp>$ = &$<v>2;
  }
  ;

format_call:
  NAME '(' attributelist ')' {
    int ***tmp_eval;
    int i,j,k;
#ifdef EJSCCDEBUG
    if ( ejsccdebug ) {
      printf("ejsccdebug: Format call '%s' found.\n", $<v.value.d>1);
      fflush(stdout);
    }
#endif
    $<v.type>$ = tOb;
    $<v.value.o.objName>$ = $<v.value.d>1;
    $<v.value.o.type>$ = Format;
    /* Allocate memory for argument lists */
    $<v.value.o.arguments>$ = (tVariable**)malloc(2*sizeof(tVariable*));
    $<v.value.o.arguments>$[0] = $<vp>3;
    $<v.value.o.arguments>$[1] = NULL;
    tmp_eval = $<v.value.o.argumentEvalId>$ = 
      (int ***)malloc(2 * sizeof(int **));
    for ( i=0 ; i<2 ; i++ ) {
      tmp_eval[i] = (int **)malloc(MAXVARS * sizeof(int*));
      for ( j=0 ; j<MAXVARS ; j++ ) {
	tmp_eval[i][j] = (int *)malloc(MAXSYMS * sizeof(int));
	for ( k=0 ; k<MAXSYMS ; tmp_eval[i][j][k++] = -1 );
      }
    }
    /* Allocate memory for return values and reset them */
    $<v.value.o.returnValues>$ = (char **)malloc(MAXSYMS * sizeof(char *));
    memset($<v.value.o.returnValues>$, (int)NULL, MAXSYMS * sizeof(char *));
    /* Formats don't have formats... */
    $<v.value.o.formats>$ = NULL;
    $<v.value.o.formatEvalId>$ = NULL;
    $<v.scope>$ = currentSym;
  }
  ;

codeblock:
  BEGIN_BLOCK ';' construction END_BLOCK { $<b>$ = true; }
  | { $<b>$ = false; }
  ;

number:
  INT { $<v>$ = $<v>1; }
  | FLOAT { $<v>$ = $<v>1; }
  ;

%%

#include "ejsc_lexer.c"
