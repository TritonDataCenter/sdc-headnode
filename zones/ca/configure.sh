#!/bin/bash

function cafail
{
	echo "fatal: $*" >&2
	exit 1
}

function casetprop
{
	local svc=$1 prop=$2 value=$3
	[[ -n $value ]] || cafail "no value specified for $svc $prop"
	svccfg -s $svc setprop com.joyent.ca,$prop = \
	    astring: "$value" || cafail "failed to set $svc $prop = $val"
}

#
# Update the SMF configuration to reflect this headnode's configuration.
#
svcadm disable -s caconfigsvc:default || cafail "failed to disable configsvc"
casetprop caconfigsvc:default caconfig/amqp-host "$CA_AMQP_HOST"
casetprop caconfigsvc:default caconfig/mapi-host "$CA_MAPI_HOST"
casetprop caconfigsvc:default caconfig/mapi-port "$CA_MAPI_PORT"
casetprop caconfigsvc:default caconfig/mapi-user "$CA_MAPI_USER"
casetprop caconfigsvc:default caconfig/mapi-password "$CA_MAPI_PASSWORD"
svcadm refresh caconfigsvc:default || cafail "failed to refresh configsvc"
svcadm enable -s caconfigsvc:default || cafail "failed to re-enable configsvc"

fmris=$(svcs -H -ofmri caaggsvc)
for fmri in $fmris; do
	svcadm disable -s $fmri || cafail "failed to disable $fmri"
	casetprop $fmri caconfig/amqp-host "$CA_AMQP_HOST"
	svcadm refresh $fmri || cafail "failed to refresh $fmri"
	svcadm enable -s $fmri || cafail "failed to re-enable $fmri"
done
