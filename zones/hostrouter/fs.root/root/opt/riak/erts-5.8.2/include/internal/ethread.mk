#
# %CopyrightBegin%
# 
# Copyright Ericsson AB 2004-2009. All Rights Reserved.
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

# ----------------------------------------------------------------------


# Name of the library where the ethread implementation is located
ETHR_LIB_NAME=ethread

# Command-line defines to use when compiling
ETHR_DEFS=-DUSE_THREADS  -D_THREAD_SAFE -D_REENTRANT -DPOSIX_THREADS -D_POSIX_PTHREAD_SEMANTICS

# Libraries to link with when linking
ETHR_LIBS=-lethread -lerts_internal_r -lpthread  -lkstat

# Extra libraries to link with. The same as ETHR_LIBS except that the
# ethread library itself is not included.
ETHR_X_LIBS=-lpthread  -lkstat

# The name of the thread library which the ethread library is based on.
ETHR_THR_LIB_BASE=pthread

# ----------------------------------------------------------------------
