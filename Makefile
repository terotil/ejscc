# Copyleft 2002, Tero Tilus <tero@tilus.net>
#
# $Id: Makefile,v 1.7 2002/07/16 10:48:25 terotil Exp $
#
# This file is part of ejscc, a program to compile Extended Java
# Sketchpad Constructions to ordinary syntax.
#
# Ejscc is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.  
# 
# Ejscc is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.  
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
# USA 

# C compiler and options
CC=gcc
CFLAGS:=-Wall
# Uncomment following lines to (not) produce debugging code
#   Parser and lexer debug, 'export YYDEBUG=n' to activate
CFLAGS:=$(CFLAGS) -DYYDEBUG
#   Compiler debug, 'export EJSCCDEBUG=1' to activate
CFLAGS:=$(CFLAGS) -DEJSCCDEBUG
#   Debug symbols
CFLAGS:=$(CFLAGS) -g
#   Skip assertions
#CFLAGS:=$(CFLAGS) -DNODEBUG


# Files to make
FILES=ejsc_lexer.c ejsc_parser.c ejscc

# Lex and options
LEX=lex
LFLAGS=

# Yacc and options
YACC=yacc
YFLAGS=


# Version number
EJSCC_VERSION=`grep 'define EJSCC_VERSION' ejscc.c | awk '{print substr($$3, 2, length($$3)-2)}'`
# Release files
RELFILE_BIN=ejscc_$(EJSCC_VERSION)_bin.tar.gz
RELFILE_SRC=ejscc_$(EJSCC_VERSION)_src.tar.gz
RELFILES_COMMON=ejscc/COPYING ejscc/README ejscc/ChangeLog ejscc/doc/manual.{txt,html} ejscc/test
RELFILES_BIN=ejscc/ejscc
RELFILES_SRC=ejscc/ejscc.c ejscc/ejsc_lexer.c ejscc/ejsc_parser.c ejscc/ejsc_parser.lex ejscc/ejsc_parser.y ejscc/Makefile ejscc/TODO ejscc/doc/manual.xml
RELFILES_EXCLUDE=--exclude=*CVS* --exclude=*~

# LDP style doc.  Comment out to go with std docbook
LDP_DSL=-d /home/terotil/usr/docbook/html/ldp.dsl

all : $(FILES) Makefile

ejsc_lexer.c : ejsc_parser.lex
	$(LEX) $(LFLAGS) -oejsc_lexer.c ejsc_parser.lex

ejsc_parser.c : ejsc_parser.y
	$(YACC) $(YFLAGS) -o ejsc_parser.c ejsc_parser.y

ejscc : ejsc_lexer.c ejsc_parser.c ejscc.c
	$(CC) $(CFLAGS) -o ejscc ejscc.c

.PHONY : clean
clean :
	-rm -f $(FILES)
	-rm -f *~
	-rm -f test/*~
	-rm -f test/*.pp
	-rm -f test/*.jsc

.PHONY : clean_doc
clean_doc :
	-rm -f doc/*.txt
	-rm -f doc/*.html
	-rm -f doc/*~

.PHONY : doc
doc : clean_doc
	-docbook2html $(LDP_DSL) -u -o doc/ doc/manual.xml
	-tidy -config doc/tidyconfig -modify -quiet doc/manual.html
	-links -dump doc/manual.html > doc/manual.txt

.PHONY : source_release
source_release : clean doc ejsc_parser.c ejsc_lexer.c
	rm -f ../$(RELFILE_SRC)
	tar --create --gzip --file=../$(RELFILE_SRC) --directory=../ $(RELFILES_EXCLUDE) --verbose $(RELFILES_COMMON) $(RELFILES_SRC)

.PHONY : binary_release
binary_release : all doc
	rm -f ../$(RELFILE_BIN)
	tar --create --gzip --file=../$(RELFILE_BIN) --directory=../ $(RELFILES_EXCLUDE) --verbose $(RELFILES_COMMON) $(RELFILES_BIN)
