#!/usr/bin/bash
#
# Upgrade other "stuff". Manual upgrade requirements that come up.
# See the "other upgrades" section in README.md.
#

if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail


#---- support stuff

function fatal
{
    echo "$0: fatal error: $*"
    exit 1
}


#---- mainline

# -- HEAD-1910, OS-2654: maintain_resolvers=true

# 1. Update the sapi services.
SDC_APP=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
[[ -n "$SDC_APP" ]] || fatal "could not determine 'sdc' SAPI app"
for data in $(sdc-sapi /services?application_uuid=$SDC_APP | json -H -a uuid name params.maintain_resolvers -d,); do
    svc_uuid=$(echo "$data" | cut -d, -f1)
    svc_name=$(echo "$data" | cut -d, -f2)
    maintain_resolvers=$(echo "$data" | cut -d, -f3)
    if [[ "$maintain_resolvers" != "true" ]]; then
        echo "Set params.maintain_resolvers on service $svc_uuid ($svc_name)."
        echo '{"params": {"maintain_resolvers": true}}' | sapiadm update $svc_uuid
    fi
done

# 2. Update current core VMs. To work, this depends on ZAPI-472,
#    https://mo.joyent.com/vmapi/commit/8f3a47d, which added 'update' workflow
#    version 7.0.7. So we need at least that version.
ufds_admin_uuid=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
update_workflow_vers=$(sdc-workflow /workflows \
    | json -Ha -c '/^update-[\d\.]+$/.test(this.name)' -e 'this.ver=this.name.split("-").slice(-1)[0]' ver | sort)
# TODO: I'm not sure how to check semver *greater than or equal* to 7.0.7,
#       so just checking for 7.0.7 presence.
if [[ "$(echo "$update_workflow_vers" | grep '7\.0\.7' || true)" == "7.0.7" ]]; then
    sdc-vmapi /vms?state=active\&owner_uuid=$ufds_admin_uuid \
        | json -Ha uuid alias maintain_resolvers \
        | while read uuid alias maintain_resolvers; do
        if [[ "$maintain_resolvers" != "true" ]]; then
            sdc-vmapi /vms/$uuid?action=update -X POST -d '{"maintain_resolvers": true}' \
                | sdc sdc-waitforjob
        fi
    done
else
    echo "Skip HEAD-1910 upgrade until VMAPI upgraded with ZAPI-472."
fi


# -- HEAD-1916: SERVICE_DOMAIN on papi svc, PAPI_SERVICE/papi_domain on sdc app

SDC_APP=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
DOMAIN=$(sdc-sapi /applications/$SDC_APP | json -H metadata.datacenter_name).$(sdc-sapi /applications/$SDC_APP | json -H metadata.dns_domain)
papi_domain=papi.$DOMAIN

papi_service=$(sdc-sapi /services?name=papi | json -Ha 0.uuid)
if [[ -n "$papi_service" ]]; then
    has_it=$(sdc-sapi /services/$papi_service | json -H metadata.SERVICE_DOMAIN)
    if [[ -z "$has_it" ]]; then
        sapiadm update $papi_service metadata.SERVICE_DOMAIN=$papi_domain
    fi
    sapiadm update $SDC_APP metadata.PAPI_SERVICE=$papi_domain
    sapiadm update $SDC_APP metadata.papi_domain=$papi_domain
fi

