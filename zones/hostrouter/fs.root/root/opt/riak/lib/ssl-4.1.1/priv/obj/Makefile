#
# %CopyrightBegin%
# 
# Copyright Ericsson AB 1999-2009. All Rights Reserved.
# 
# The contents of this file are subject to the Erlang Public License,
# Version 1.1, (the "License"); you may not use this file except in
# compliance with the License. You should have received a copy of the
# Erlang Public License along with this software. If not, it can be
# retrieved online at http://www.erlang.org/.
# 
# Software distributed under the License is distributed on an "AS IS"
# basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
# the License for the specific language governing rights and limitations
# under the License.
# 
# %CopyrightEnd%
#

# Makefile for SSL on Unix
# 
# Placed in obj directory. 
#
CC = gcc
	
BINDIR = ../bin
LIBS = -ldl -lm -lpthread -lrt  -lsocket -lnsl
SSL_LIBDIR = /opt/local/lib 
OBJS = ../priv/obj/i386-pc-solaris2.11/esock.o ../priv/obj/i386-pc-solaris2.11/debuglog.o ../priv/obj/i386-pc-solaris2.11/esock_poll.o ../priv/obj/i386-pc-solaris2.11/esock_osio.o ../priv/obj/i386-pc-solaris2.11/esock_utils.o ../priv/obj/i386-pc-solaris2.11/esock_posix_str.o ../priv/obj/i386-pc-solaris2.11/esock_openssl.o%

$(BINDIR)/ssl_esock: $(OBJS)
	$(CC) -L$(SSL_LIBDIR) -Wl,-R$(SSL_LIBDIR) -o $@ $^ \
		$(LIBS) -lssl -lcrypto
