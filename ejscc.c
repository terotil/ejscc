/* Copyleft 2002, Tero Tilus <tero@tilus.net>
 *
 * $Id: ejscc.c,v 1.16 2002/08/15 07:21:56 terotil Exp $
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
 **/
#define EJSCC_VERSION "0.1.9"
#define EVALIDSTEP 1000
#include <stdio.h>
#include <string.h>
#include <assert.h>

// Debugging helpers
#define HEP(X) {fflush(stdout);printf("{ Hep! (%d) }\n", X);fflush(stdout);}
// define DPR(STR) {fflush(stdout);printf("{ %s }\n", STR);fflush(stdout);}
#define DPR(STR) {}

/* Different types of variables */
typedef enum { false=0, true } tBoolean;
typedef enum { Object, Definition, Format } tObjType;

typedef struct {
  char *objName;
  tObjType type;
  struct v **arguments;
  int ***argumentEvalId;
  char **returnValues;
  struct v *formats;
  int **formatEvalId;
} tObject;                 /* Construction object */
typedef char *tString;     /* String literal */
typedef int tInt;          /* Integer */
typedef double tFloat;     /* Float */
typedef char *tIdentifier; /* Reference to symbol table */

/* Enumeration of variable types */
typedef enum { tOb, tSt, tIn, tFl, tId, tNull } tVarType;
/* Value of variable */
typedef union {
  tObject o;
  tString s;
  tInt i;
  tFloat f;
  tIdentifier d;
} tVarValue;

/* Variable */
typedef struct v {
  int evalId;          /* To keep track whether re-evaluation is needed */
  tVarType type;       /* Type of the variable */
  tVarValue value;     /* Value ... */
  struct s *scope;
} tVariable;

/* Symbol */
typedef struct s {
  tIdentifier symName; /* Name of the symbol */
  int symIndex;        /* Index of the sumbol */ /*FIXME: Belongs to tObject!!!*/
  tVariable *symValue; /* Pointer to value of symbol */
  int symTSize;        /* Size of symbol table*/
  struct s **symTable; /* Symbol table used when evaluating the value
                          of this symbol. */
  struct s *parentSym; /* Pointer to parent symbol */
  tBoolean beingCompiled; /* Is this symbol currently being compiled?
			     This is a flag to track recursive
			     definitions, which for now are
			     prohibited. */
} tSymbol;

/* Global variables */
//extern int opterr=0;
int ejsccdebug=false;
int objectIndex; /* Index of last emitted construction objec */
//tObject nullObj = {-2, NULL, false, NULL, NULL, NULL, NULL};
tVariable nullVar = {-2, tNull, {{NULL, Object, NULL, NULL, NULL, NULL, NULL}}, NULL};
tSymbol nullSym = {"", -1, NULL, 0, NULL, NULL};
tSymbol rootSym = {"global", 0, NULL, 0, NULL, NULL};
tSymbol *currentSym = &rootSym; /* For parser */

/* Getopt variables */
extern char *optarg;
extern int optind, opterr, optopt;

/* Files */
char *infilename=NULL;
char *outfilename=NULL;
FILE *infile;
FILE *outfile;

const char *ejsc_ext = "ejsc";
const char *jsc_ext  = "jsc";

tBoolean preprocess = false;

/* Produce debugging output */
void dbout(char *str) {
  if ( ejsccdebug ) {
    assert(str != NULL);
    printf("ejsccdebug: %s", str);
    fflush(stdout);
  }
}

#include "ejsc_parser.c"

char *compile_(tVariable *sv);
char *compile__(tSymbol *sym);

char *recurse(tSymbol *sym) {
  int i;
  tSymbol **st;
  char *return_value = NULL;
  char *tmpretval1 = "{ Construction hasn't got return value! }";
  char *tmpretval2 = tmpretval1;
  assert(sym != NULL);
  st = (*sym).symTable; /* Temporary pointer to symbol table */
  if ( st != NULL ) {
    for (i=0; ((st[i])!=NULL); i++) {
      tmpretval2 = compile__(st[i]);
      if ( (*((*(st[i])).symValue)).type == tOb ) {
	if ( strcmp((*(st[i])).symName,
		    (*sym).symName) == 0 ) {
	  // Return value from symbol having the same name than it's
	  // parent symbol is preferred as return value.
	  return_value = tmpretval2;
	} else {	  
	  // "Default" return value is the return value from the last
	  // construction compiled.
	  tmpretval1 = tmpretval2;
	}
      }
    }
  }
  if ( return_value == NULL ) { return_value = tmpretval1; }
  return return_value;
}

tSymbol *resolve(tSymbol *sym, tIdentifier id) {
  int i;
  assert(sym != NULL);
  assert(id != NULL);
  assert(strcmp(id,"") != 0);
#ifdef EJSCCDEBUG
    if ( ejsccdebug ) {
      printf("ejsccdebug: Resolving reference to symbol '%s' in '%s'.\n", 
	     id, (*sym).symName);
      fflush(stdout);
    }
#endif
  /* First try finding id from given scope */
  i = get_sym_index(sym, id);
  if ( i < 0 ) {
    /* Descend into parent scope on failure */
    if ( (*sym).parentSym != NULL ) {
      return resolve((*sym).parentSym, id);
    }
    /* Couldn't be resolved... */
    return NULL;
  }
  return ((*sym).symTable[i]);
}

/* Retrieve the "fingerprint" of construction call.  On later calls  */
int **get_fingerprint(tVariable **args) {
#define HEI(X,Y) {fflush(stdout);printf(X,Y);fflush(stdout);}
  tVariable *tmpvar;
  tVariable *tmpvar1;
  tSymbol *tmpsym;
  int **fingerprint;
  int i, j, k;
  // FIXME: Mallocs could propably be done during variable browsing --> lower mem consumption
  fingerprint = malloc(MAXARGLISTS*sizeof(int*));
  for (i=0; i<MAXARGLISTS; i++ ) {
    fingerprint[i] = malloc(MAXVARS*sizeof(int));
    memset(fingerprint[i], -2, MAXVARS*sizeof(int)); // Reset fingerprint
  }
  // Browse variables
  if ( args != NULL ) {
    //       HEI("\t%s{","");
    i=0;
    while ( args[i] != NULL ) {
      tmpvar = args[i];
      j=0;
      while (tmpvar[j].type != tNull) {
	assert(j<MAXSYMS);
	// Store evalId to k
	k = tmpvar[j].evalId;
	// "Deep" evalId chech for identifiers. 
	tmpvar1 = &(tmpvar[j]);
	while ( (*tmpvar1).type == tId ) {
	  tmpsym = resolve((*tmpvar1).scope, (*tmpvar1).value.d);
	  if ( tmpsym != NULL ) {
	    tmpvar1 = (*tmpsym).symValue;
	    k = (*tmpvar1).evalId;
	  } else {
#ifdef EJSCCDEBUG
	    if ( ejsccdebug ) {
	      printf("ejsccdebug: Unresolved reference to '%s', skipping check.\n", 
		     (*tmpvar1).value.d);fflush(stdout);
	    }
#endif
	    k = tmpvar[j].evalId; // Fallback to original identifier's evalId
	    tmpvar1 = &nullVar;
	  }
	} // END "Deep" evalId chech for identifiers.

	// evalId's must be non-negative!
	assert(k>=0);
	// Remember recieved evalId 
	fingerprint[i][j] = k;
	//		HEI(" %d",k);
	j++;
      }
      //            HEI("%s\n\t ","");
      i++; // Next parameter list
    }
    //        HEI("%s fingerprint }\n","");
  }
  return fingerprint;
}

int match_fingerprint(int ***argIds, int **fingerprint) {
  /* Does any of the previous calls match to the list of evalIds
     we have in hand? */
  int i, j, k;  i=j=k=0;
  while ( argIds[i][j][k] >= 0 ) {
    while ( argIds[i][j][k] >= 0 ) {
      if ( argIds[i][j][k] !=
	   fingerprint[i][j] ) {
	// This fingerprint didn't match, try next one.
	i=0; j=0; k++;
	assert(k<MAXSYMS);
      } else {
	j++; // Next parameter
      }
      assert(j<MAXVARS);
    }
    i++; // Next parameter list
    j=0; // Start from the beginning of next parameter list
    assert(i<MAXARGLISTS);
  }
  return k;
}

char *compile__(tSymbol *sym) {
  char *returnValue;
  assert(sym != NULL);
  assert((*sym).symValue != NULL);
#ifdef EJSCCDEBUG
  if ( ejsccdebug ) {
    printf("ejsccdebug: Compiling sym name '%s', val %s (%d)\n", 
	   (*sym).symName, get_name((*sym).symValue), (int)sym);fflush(stdout);
    fflush(stdout);
  }
#endif
  /* Track down recursive definitions */
  if ( (*sym).beingCompiled ) {
    /* If we're asked to compile something which is currently being
       compiled it means that we've found a definition loop. */
    fprintf(stderr, "Fatal error: Recursive definition of '%s'.\n", (*sym).symName);
    exit(1);
  } else {
    /* Not being compiled: "lock", compile and "release" */
    (*sym).beingCompiled = true;
    returnValue = compile_((*sym).symValue);
    (*sym).beingCompiled = false;
    return returnValue;
  }
}

char *compile_(tVariable *sv) {
  tSymbol *tmpsym;
  tVariable *tmpvar;
  char *tmp, *tmp1; /* Compile buffer */
  tBoolean emit = false; /* Need to (re-)emit construction? */
  int i, j, k;
  int **fingerprint;
  assert(sv != NULL);
#define EJSCCBUFSIZE 256
  tmp = (char *)malloc(EJSCCBUFSIZE*sizeof(char));
  tmp1 = (char *)malloc(EJSCCBUFSIZE*sizeof(char));
  memset(tmp,  (char)0, EJSCCBUFSIZE); /* Clear */
  memset(tmp1, (char)0, EJSCCBUFSIZE); /* Clear */
  switch ( (*sv).type ) {
  case tOb: /* Construction object */
    if ( (*sv).value.o.type != Definition ) {
      /* Call to construction object (user or builtin) */
      /* Check if we have a call to user function */
      tmpsym = resolve((*sv).scope, (*sv).value.o.objName);
      if ( tmpsym != NULL ) {
	/* Matching user function found! */
	if ( (*(*tmpsym).symValue).type != tOb ) {
	  yyerror("Non-construction called!");
	}

	/* Tracking and caching of user defined constructions not
	   currently done.  Task is inherited to constructions forming
	   this user defined construction. */

	// Get fingerprint of parameter list
	fingerprint = get_fingerprint((*sv).value.o.arguments);
	// Try to match it to previous fingerprints
	k = match_fingerprint((*sv).value.o.argumentEvalId, fingerprint);
	if ( (*sv).value.o.returnValues[k] != NULL ) {
	  // Match!!!
	  return (*sv).value.o.returnValues[k];
	}

	/* Set user function parameters / formats from parameters /
	   formats of current call. */
	// FIXME: Check lengths of parameter lists!
	i=j=0;
	while ( (*(*tmpsym).symValue).value.o.arguments[i] != NULL ) {
	  tmpvar = (*(*tmpsym).symValue).value.o.arguments[i];
	  while (tmpvar[j].type != tNull) {
	    /* Function definition's parameter list must contain only
	       identifiers. */
	    if ( tmpvar[j].type != tId ) {
	      fprintf(stderr, "Fatal error: Parameter %d/%d in %s not identifier.\n",
		      i,j,get_name((*tmpsym).symValue));
	      exit(1);
	    }
	    if ( ((*sv).value.o.arguments != NULL) &&
		 ((*sv).value.o.arguments[i] != NULL) &&
		 ((*sv).value.o.arguments[i][j].type != tNull) ) {
	      append_symbol_to_symtable(tmpvar[j].value.d, 
					&((*sv).value.o.arguments[i][j]), 
					tmpsym);
	    }
	    j++;
	  }
	  j=0;
	  i++;
	}

	/* Recurse into symbol */
#ifdef EJSCCDEBUG
	if ( ejsccdebug ) {
	  printf("ejsccdebug: User function, recurse '%s', index %d.\n", 
		 (*(*tmpsym).symValue).value.o.objName, 
		 (*(*(*tmpsym).symValue).scope).symIndex);
	  fflush(stdout);
	}
#endif
        i = (*(*tmpsym).symValue).evalId;
	free(tmp);
	tmp = recurse(tmpsym);
	//        j = (*(*tmpsym).symValue).evalId;  // Not used?
	if ( i != (*(*tmpsym).symValue).evalId ) {
	  // If evalId of user construction changed, we must change
	  // the evalId of this call to too.  Construction and call to
	  // construction are different.  Construction's evalId is
	  // updated during call, but evalId checking is done to call
	  // (not construction).
	  (*sv).evalId++;
	}
	free(tmp1);
	/* Update parent symbol's return value */
	if ( (*(*sv).scope).parentSym != NULL ) {
	  (*(*(*sv).scope).parentSym).symIndex = (*(*sv).scope).symIndex;
#ifdef EJSCCDEBUG
	  if ( ejsccdebug ) {
	    printf("ejsccdebug: Update '%s' to %d \n", 
		   (*(*(*sv).scope).parentSym).symName,
		   (*(*(*sv).scope).parentSym).symIndex); fflush(stdout);
	  }
#endif
	}

	// Update fingerprint of this call to argumentEvalId array
	i=0;
	while ( fingerprint[i][j] >= 0 ) {
	  while ( fingerprint[i][j] >= 0 ) {
	    (*sv).value.o.argumentEvalId[i][j][k] = fingerprint[i][j];
	    j++;
	    assert(j<MAXVARS);
	  }
	  j=0;
	  i++;
	  assert(i<MAXARGLISTS);
	}
	// "Save" return value
	(*sv).value.o.returnValues[k] = tmp;

	return tmp;
      } /* End of user construction handling */

      if ( ((*sv).evalId % EVALIDSTEP) == 0 ) {
	(*sv).evalId++;
	emit = true;
      }

      /* Variables */
      if ( (*sv).value.o.arguments != NULL ) {
	i=j=0;
	while ( (*sv).value.o.arguments[i] != NULL ) {
	  strcat(tmp, "(");
	  tmpvar = (*sv).value.o.arguments[i];
	  while (tmpvar[j].type != tNull) {
	    assert(j<MAXSYMS);
	    if ( j != 0 ) { strcat(tmp, ","); }
#ifdef EJSCCDEBUG
	    if ( ejsccdebug ) {
	      printf("ejsccdebug: Parameter: %s\n", get_name(&(tmpvar[j])));
	      fflush(stdout);
	    }
#endif
	    strcat(tmp, compile_(&(tmpvar[j])));
	    j++;
	  }
	  strcat(tmp, ")");
	  j=0;
	  i++;
	}
      } // End of Variables -loop

      // Get fingerprint of parameter list
      fingerprint = get_fingerprint((*sv).value.o.arguments);

      /* Does any of the previous calls match to the list of evalIds
	 we have in hand? */
      k = match_fingerprint((*sv).value.o.argumentEvalId, fingerprint);

      if ( (*sv).value.o.returnValues[k] == NULL ) {
	// This construction hasn't been called with these parameters
	// before.
	emit = true; // Emit this construction
	// Update fingerprint of this call to argumentEvalId array
	i=j=0;
	while ( fingerprint[i][j] >= 0 ) {
	  while ( fingerprint[i][j] >= 0 ) {
	    (*sv).value.o.argumentEvalId[i][j][k] = fingerprint[i][j];
	    j++;
	    assert(j<MAXVARS);
	  }
	  j=0;
	  i++;
	  assert(i<MAXARGLISTS);
	}
      }

      /* Formats */
      if ( (*sv).value.o.formats != NULL ) {
	strcat(tmp, "[");
	i=0;
	while ( (*sv).value.o.formats[i].type != tNull ) {
#ifdef EJSCCDEBUG
	  if ( ejsccdebug ) {
	    printf("ejsccdebug: Format: %s\n", get_name(&((*sv).value.o.formats[i])));
	    fflush(stdout);
	  }
#endif
	  if ( i != 0 ) { strcat(tmp, ","); }
	  strcat(tmp, compile_(&((*sv).value.o.formats[i])));
	  i++;
	}
	strcat(tmp, "]");
      }

      /* Render construction object. */
      if ( (*sv).value.o.type == Format ) {
	// Swap tmp and tmp1
	i = (int)tmp1;
	tmp1 = tmp;
	tmp = (char *)i;
	sprintf(tmp, "%s%s", (*sv).value.o.objName, tmp1);
      } else {
	if ( emit ) {
	  // Parent's return value is updated to i
	  i = (*(*sv).scope).symIndex = ++objectIndex; 
	  (*sv).evalId++;
	  // FIXME: Must figure out how to properly mark user
	  // constructions "dirty" to make tracking work.
	  // DIRTYFIX START
	  if ( (*(*sv).scope).symValue != NULL ) {
	    // Makes sense only with nested constructions, otherwise
	    // updates object's own evalId.
	    (*(*(*sv).scope).symValue).evalId++; 
	    if ( (*(*(*sv).scope).parentSym).symValue != NULL ) {
	      // Logical parent...
	      (*(*(*(*sv).scope).parentSym).symValue).evalId++;
	    }
	  }
	  // DIRTYFIX END
	  fprintf(outfile, "{%4d } %s%s;\n", i, (*sv).value.o.objName, tmp);
	  tmp[0] = '\0';
	  sprintf(tmp, "%d", i);
	  (*sv).value.o.returnValues[k] = tmp;
	} else {
	  // Parent's return value is updated to i
	  i = (*(*sv).scope).symIndex; 
	  // This construction has been emitted previously, we can get
	  // return value from "cache".
	  tmp = (*sv).value.o.returnValues[k];
	}
	/* Update parent symbol's return value */
	if ( (*(*sv).scope).parentSym != NULL ) {
	  (*(*(*sv).scope).parentSym).symIndex = i;
#ifdef EJSCCDEBUG
	  if ( ejsccdebug ) {
	    printf("ejsccdebug: Update '%s' to %d \n", 
		   (*(*(*sv).scope).parentSym).symName,
		   (*(*(*sv).scope).parentSym).symIndex); fflush(stdout);
	  }
#endif
	}
      }
      free(tmp1);
      return tmp;
    } else {
      /* User function, contains codeblock */
      /* Not evaluated when encountered!  Only when called.  */
#ifdef EJSCCDEBUG
      if ( ejsccdebug ) {
	printf("User construction '%s' (evaluated only when called)\n", 
	       (*(*sv).scope).symName); fflush(stdout);
      }
#endif
      free(tmp); free(tmp1);
      return "{ User construction, evaluated only when called. }";
    }
    break;
  case tSt: /* String literal */
    assert((*sv).value.s != NULL);
    free(tmp); free(tmp1);
    return (*sv).value.s;
    break;
  case tIn: /* Integer */
    free(tmp1);
    sprintf(tmp, "%d", (*sv).value.i); return tmp;
    break;
  case tFl: /* Float */
    free(tmp1);
    sprintf(tmp, "%f", (*sv).value.f); return tmp;
    break;
  case tId: /* Reference to symbol table */
    free(tmp); free(tmp1);
    /* Try to resolve reference. */ 
    tmpsym = resolve((*sv).scope, (*sv).value.d);
    if ( tmpsym != NULL ) {
#ifdef EJSCCDEBUG
      if ( ejsccdebug ) {
	printf("ejsccdebug: Resolved  '%s', found %s.\n", 
	       (*sv).value.d, get_name((*tmpsym).symValue));
	fflush(stdout);
      }
#endif
      return compile__(tmpsym);
    } else {
      /* Unresolved references are written out as-is. */
#ifdef EJSCCDEBUG
      if ( ejsccdebug ) {
	printf("ejsccdebug: '%s' unresolved, thus left as is.\n", 
	       (*sv).value.d);
	fflush(stdout);
      }
#endif
      return (*sv).value.d;
    }
    break;
  case tNull: /* Null variable */
  default:
    free(tmp); free(tmp1);
    break;
  }
  fprintf(outfile, "EI IKINÄ TÄNNE!\n");
  return "";
}

void compile(void) {

#ifdef EJSCCDEBUG
  if ( ejsccdebug ) {
    printf("\n--------------------------\nejsccdebug: Start compile.\n");
    fflush(stdout);
  }
#endif

  recurse(&rootSym);

#ifdef EJSCCDEBUG
  if ( ejsccdebug ) {
    printf("ejsccdebug: Compile done.\n--------------------------\n");
    fflush(stdout);
  }
#endif

}

void init_debug(void) {
  char *debugval;
  debugval = getenv("EJSCCDEBUG");
  if ( (debugval != NULL) && 
       (debugval[0] > '0') ) {
    ejsccdebug = true;
  }
}

void print_usage(void) {
  const char usage[] = "
ejscc - a program to compile Extended Java Sketchpad Constructions to
ordinary syntax.  Ejscc is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License.

usage: ejscc [-DhVp] [-o outputfile] [inputfile]

\t-p  Do preprocessing with C preprocessor (only when using file input)
\t-D  Enable debugging mode (available if debugging was compiled in).
\t-h  Print this one-line help and exit.
\t-V  Print version number and exit.

Currently ejscc cab use both stdin/stdout and file io.  It reads source
from stdin or specified input and writes compiled code to stdout or 
specified output file.  File '-' forces std(in/out).
";
  printf(usage);
}

void parse_options(int argc, char **argv) {
  char *tmp;
  int c;
  /* First deal with options */
  while (1) {
    c = getopt(argc,argv,"Dho:pV");
    if (c==-1) break;
    switch (c) {
    case 'h': // Help
      print_usage();
      fflush(stdout);
      exit(0);
      break;
    case 'V': // Version
      printf("ejscc version: %s\n", EJSCC_VERSION);
      fflush(stdout);
      exit(0);
      break;
    case 'D': // Debug mode
      ejsccdebug = true;
      break;
    case 'o': // Output file
      outfilename = optarg;
      break;
    case 'p': // Do preprocessing
      preprocess = true;
      break;
    }
  }
  /* Next parse non-options */
  if ( optind < argc && 
       argv[optind][0] != '-' ) {
    infilename = argv[optind];
    if ( outfilename == NULL ) {
      outfilename = malloc(256 * sizeof(char));
      strcpy(outfilename, infilename);
      tmp = strrchr(outfilename, '.');
      if ( tmp != NULL ) {
	tmp[1] = '\0';
      }
      strcat(outfilename, jsc_ext);
    }
  }
}

void open_files() {
  char *tmp_filename;
  char *tmp_command;
  /* Preprocessing */
  if ( preprocess ) {
    if ( infilename == NULL ) {
      fprintf(stderr, "Preprocessing not available when reading from stdin.\n");
      exit(1);
    }
    tmp_filename = malloc(256 * sizeof(char));
    strcpy(tmp_filename, infilename);
    strcat(tmp_filename, ".pp");
    tmp_command = malloc(256 * sizeof(char));
    sprintf(tmp_command, "cpp -E -o \"%s\" \"%s\"", tmp_filename, infilename);
    system(tmp_command);
  } else {
    tmp_filename = infilename;
  }
  /* Output */
  if ( outfilename != NULL && 
       outfilename[0] != '-' ) {
    if ( (outfile = fopen(outfilename, "w")) == NULL ) {
      fprintf(stderr, "Couldn't open output file '%s'.", outfilename);
      exit(1);
    }
  } else {
    outfile = stdout;
  }
  /* Input */
  if ( tmp_filename != NULL ) {
    if ( (infile = fopen(tmp_filename, "r")) == NULL ) {
      fprintf(stderr, "Couldn't open input file '%s'.", tmp_filename);
      exit(1);
    }
    yyin = infile;
  } else {
    infile = stdin;
  }
  assert(infile != NULL);
  assert(outfile != NULL);
}

void close_files() {
  if ( outfile != stdout ) {
    fclose(outfile);
  }
  if ( infile != stdin ) {
    fclose(infile);
  }
}

int main(int argc, char **argv) {
  init_debug();
  parse_options(argc, argv);
  open_files();
  yyparse();
  objectIndex = 0;
  compile();
  close_files();
  return 0;
}
