#!/usr/bin/bash


/usr/bin/bootparams | grep "headnode=true"

if [[ $? == 0 ]]; then
    /sbin/headnode
else
    /sbin/joysetup
fi;

return $?

