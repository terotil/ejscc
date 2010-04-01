/* Copyleft 2002, Tero Tilus <tero@tilus.net>
 *
 * $Id: ejsc_parser.lex,v 1.5 2002/07/10 09:16:47 terotil Exp $
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
d   [0-9]
l   [A-Za-z]
nl  [A-Za-z0-9_ \&\/]
%{
  void malloc_copy(char **to, const char *from) {
    /* Allocate storage and make a copy of 'from' */
    (*to) = (char *) malloc( (strlen(from)+1) * sizeof(char) );
    strcpy((*to), from);
  }
%}
%%

begin { /* BEGIN ******************************************************/
  int i;
  i = check_symtable(currentSym);
  if ( i<0 ) { yyerror("Fatal error: symTable full."); exit(1); }
  (*currentSym).symTable[i] = (tSymbol *)malloc(sizeof(tSymbol));
  (*((*currentSym).symTable[i])) = nullSym;
  (*((*currentSym).symTable[i])).symTSize = 0;
  (*((*currentSym).symTable[i])).symTable = NULL;
  (*((*currentSym).symTable[i])).parentSym = currentSym;
#ifdef EJSCCDEBUG
	if ( ejsccdebug ) {
	  printf("ejsccdebug: Begin code block. (%d, %d)\n", 
		 (int)currentSym, (int)(*currentSym).symTable[i]);
	  fflush(stdout);
	}
#endif
  currentSym = (*currentSym).symTable[i];
  return BEGIN_BLOCK;
}

end { /* END **********************************************************/
#ifdef EJSCCDEBUG
	if ( ejsccdebug ) {
	  printf("ejsccdebug: End code block. (%d, %d)\n", 
		 (int)currentSym, (int)(*currentSym).parentSym);
	  fflush(stdout);
	}
#endif
  currentSym = (*currentSym).parentSym;
  return END_BLOCK;
}

({l}({nl}*({l}|{d})))|({l}) { /* NAME *********************************/
  malloc_copy(&yylval.v.value.s, yytext);
  yylval.v.type = tId;
  yylval.v.scope = currentSym;
  yylval.v.evalId = evalIndex; evalIndex += EVALIDSTEP;
  return NAME; 
}

([-+][ ]*)?{d}+          { /* INT *************************************/
  yylval.v.value.i = atoi(yytext); 
  yylval.v.type = tIn;
  yylval.v.scope = currentSym;
  yylval.v.evalId = evalIndex; evalIndex += EVALIDSTEP;
  return INT; 
}

([-+][ ]*)?{d}+(\.{d}+)? { /* FLOAT ***********************************/
  yylval.v.value.f = atof(yytext); 
  yylval.v.type = tFl;
  yylval.v.scope = currentSym;
  yylval.v.evalId = evalIndex; evalIndex += EVALIDSTEP;
  return FLOAT; 
}

\'([^\']|\n)*\'          { /* STRING **********************************/
  malloc_copy(&yylval.v.value.s, yytext); 
  yylval.v.type = tSt;
  yylval.v.scope = currentSym;
  yylval.v.evalId = evalIndex; evalIndex += EVALIDSTEP;
  return STRING; 
}

\{([^\}]|\n)*\}          { /* COMMENT *********************************/
  /* JSC (pascal style) curly brace comment block */
  malloc_copy(&yylval.v.value.s, yytext);
  yylval.v.type = tSt;
  yylval.v.scope = currentSym;
  yylval.v.evalId = evalIndex; evalIndex += EVALIDSTEP;
  return COMMENT; 
}
\/\*(\*[^\/]|[^\*]|\n)*\*\/  { /* COMMENT *****************************/
  /* C++ comment block */
  malloc_copy(&yylval.v.value.s, yytext);
  yylval.v.type = tSt;
  yylval.v.scope = currentSym;
  yylval.v.evalId = evalIndex; evalIndex += EVALIDSTEP;
  return COMMENT; 
}
\/\/.*$                   { /* COMMENT *********************************/
  /* C line comment */
  malloc_copy(&yylval.v.value.s, yytext);
  yylval.v.type = tSt;
  yylval.v.scope = currentSym;
  yylval.v.evalId = evalIndex; evalIndex += EVALIDSTEP;
  return COMMENT; 
}
#.*$                     { /* COMMENT *********************************/
  /* Shellscript line comment.  This helps occasional non-preprocessed
     compiling of sources containing preprocessor directives, which
     start with hash. */
  malloc_copy(&yylval.v.value.s, yytext);
  yylval.v.type = tSt;
  yylval.v.scope = currentSym;
  yylval.v.evalId = evalIndex; evalIndex += EVALIDSTEP;
  return COMMENT; 
}

[\(\)\[\]\,\;=]          { /* Special characters **********************/
  return *yytext;          /* consisting () [] , ; and =              */
}

[\ \t\n\r]               { /* Skip whitespace *************************/
  if ( yytext[0] == '\n' ) yylineno++; /* Count lines */
}

.                        { /* Everything else triggers error **********/
  char error[255];
  sprintf(error, "Invalid character \"%s\" on line %d.", 
	  yytext, yylineno);
  yyerror(error); 
}
%%
int yywrap(void) { return 1; }
