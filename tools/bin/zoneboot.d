#!/usr/sbin/dtrace -Cs
/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2014, Joyent, Inc.
 */

#pragma D option quiet
#define START_TIME  start[curthread->t_did]

proc:::create
/zonename == $$1/
{
    printf("{\"type\": \"fork\", \"zonename\": \"%s\", \"ppid\": \"%d\", \"pid\": \"%d\", \"time\": \"%d\"}\n",
        zonename, pid, args[0]->pr_pid, timestamp);
}

proc:::start
/!START_TIME && zonename == $$1/
{
    START_TIME = timestamp;
}

proc:::exec-success
/zonename == $$1/
{
    printf("{\"type\": \"exec\", \"zonename\": \"%s\", \"pid\": \"%d\", \"execname\": \"%s\", \"time\": \"%d\", \"args\": \"%S\"}\n",
        zonename, pid, execname, timestamp, curpsinfo->pr_psargs);
}

/* When someone (setup) runs u3b5 we know it's done */
proc:::exec-success
/execname == "u3b5" && zonename == $$1/
{
    exit(0);
}

proc:::exit
/zonename == $$1/
{
    printf("{\"type\": \"exit\", \"zonename\": \"%s\", \"pid\": \"%d\", \"time\": \"%d\"}\n",
        zonename, pid, timestamp);
}
