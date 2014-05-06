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

# TODO(HEAD-1910): only do the upgrade for core VMs that are on a platform
# >=  20140212T195911Z.
#
## 2. Update current core VMs. To work, this depends on ZAPI-472,
##    https://mo.joyent.com/vmapi/commit/8f3a47d, which added 'update' workflow
##    version 7.0.7. So we need at least that version.
#ufds_admin_uuid=$(bash /lib/sdc/config.sh -json | json ufds_admin_uuid)
#update_workflow_vers=$(sdc-workflow /workflows \
#    | json -Ha -c '/^update-[\d\.]+$/.test(this.name)' -e 'this.ver=this.name.split("-").slice(-1)[0]' ver | sort)
## TODO: I'm not sure how to check semver *greater than or equal* to 7.0.7,
##       so just checking for 7.0.7 presence.
#if [[ "$(echo "$update_workflow_vers" | grep '7\.0\.7' || true)" == "7.0.7" ]]; then
#    sdc-vmapi /vms?state=active\&owner_uuid=$ufds_admin_uuid \
#        | json -Ha uuid alias maintain_resolvers \
#        | while read uuid alias maintain_resolvers; do
#        if [[ "$maintain_resolvers" != "true" ]]; then
#            echo "Set maintain_resolvers=true on VM $uuid ($alias)."
#            sdc-vmapi /vms/$uuid?action=update -X POST -d '{"maintain_resolvers": true}' \
#                | sdc sdc-waitforjob
#        fi
#    done
#else
#    echo "Skip HEAD-1910 upgrade until VMAPI upgraded with ZAPI-472."
#fi


# -- HEAD-1916: SERVICE_DOMAIN on papi svc, PAPI_SERVICE/papi_domain on sdc app

SDC_APP=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
DOMAIN=$(sdc-sapi /applications/$SDC_APP | json -H metadata.datacenter_name).$(sdc-sapi /applications/$SDC_APP | json -H metadata.dns_domain)
sapi_url=$(sdc-sapi /applications/$SDC_APP | json -H metadata.sapi-url)

papi_domain=papi.$DOMAIN
papi_service=$(sdc-sapi /services?name=papi | json -H 0.uuid)
if [[ -n "$papi_service" ]]; then
    echo "Upgrade PAPI service vars in SAPI."
    sapiadm update $papi_service metadata.SERVICE_DOMAIN=$papi_domain
    sapiadm update $papi_service metadata.sapi-url=$sapi_url
    sapiadm update $SDC_APP metadata.PAPI_SERVICE=$papi_domain
    sapiadm update $SDC_APP metadata.papi_domain=$papi_domain
fi

mahi_domain=mahi.$DOMAIN
mahi_service=$(sdc-sapi /services?name=mahi | json -H 0.uuid)
if [[ -n "$mahi_service" ]]; then
    echo "Upgrade MAHI service vars in SAPI."
    sapiadm update $mahi_service metadata.SERVICE_DOMAIN=$mahi_domain
    sapiadm update $mahi_service metadata.sapi-url=$sapi_url
    sapiadm update $SDC_APP metadata.MAHI_SERVICE=$mahi_domain
    sapiadm update $SDC_APP metadata.mahi_domain=$mahi_domain
fi


# -- INTRO-701, should have at last 4GiB mem cap on ca zone

ca_svc=$(sdc-sapi /services?name=ca | json -H 0.uuid)
ca_max_physical_memory=$(sdc-sapi /services/$ca_svc | json -H params.max_physical_memory)
if [[ $ca_max_physical_memory != "4096" ]]; then
    echo "Update 'ca' SAPI service max_physical_memory, etc."
    sapiadm update $ca_svc params.max_physical_memory=4096
    sapiadm update $ca_svc params.max_locked_memory=4096
    sapiadm update $ca_svc params.max_swap=8192
    sapiadm update $ca_svc params.zfs_io_priority=20
    sapiadm update $ca_svc params.cpu_cap=400
    sapiadm update $ca_svc params.package_name=sdc_4096
fi
ca_zone_uuid=$(vmadm lookup -1 state=running alias=ca0)
ca_zone_max_physical_memory=$(vmadm get $ca_zone_uuid | json max_physical_memory)
if [[ $ca_zone_max_physical_memory != "4096" ]]; then
    echo "Update 'ca0' zone mem cap to 4096."
    vmadm update $ca_zone_uuid max_physical_memory=4096
    vmadm update $ca_zone_uuid max_locked_memory=4096
    vmadm update $ca_zone_uuid max_swap=8192
    vmadm update $ca_zone_uuid zfs_io_priority=20
    vmadm update $ca_zone_uuid cpu_cap=400
fi

# XXX HEAD-1931. get min package values, perhaps with relevant files copied from
#     usb-headnode.git to incr-upgrade pkg. Should we have a sdc_FOO package
#     for each service, and then just update them and resize zones as
#     appropriate?
#
#     TODO: Do current new build values match the following?
#
#     Until have that, then comment the following out.
if false; then
    # rabbit 16384
    sdc_app=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
    rabbitmq_svc=$(sdc-sapi /services?application_uuid=$sdc_app\&name=rabbitmq | json -H 0.uuid)
    sapiadm update $rabbitmq_svc params.max_physical_memory=16384
    sapiadm update $rabbitmq_svc params.max_locked_memory=16384
    sapiadm update $rabbitmq_svc params.max_swap=32768
    rabbitmq_zone_uuid=$(vmadm lookup -1 state=running alias=rabbitmq0)
    vmadm update $rabbitmq_zone_uuid max_physical_memory=16384
    vmadm update $rabbitmq_zone_uuid max_locked_memory=16384
    vmadm update $rabbitmq_zone_uuid max_swap=32768
    # manatee 16384
    sdc_app=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
    manatee_svc=$(sdc-sapi /services?application_uuid=$sdc_app\&name=manatee | json -H 0.uuid)
    sapiadm update $manatee_svc params.max_physical_memory=16384
    sapiadm update $manatee_svc params.max_locked_memory=16384
    sapiadm update $manatee_svc params.max_swap=32768
    manatee_zone_uuid=$(vmadm lookup -1 state=running alias=manatee0)
    vmadm update $manatee_zone_uuid max_physical_memory=16384
    vmadm update $manatee_zone_uuid max_locked_memory=16384
    vmadm update $manatee_zone_uuid max_swap=32768
    # moray 8192
    sdc_app=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
    moray_svc=$(sdc-sapi /services?application_uuid=$sdc_app\&name=moray | json -H 0.uuid)
    sapiadm update $moray_svc params.max_physical_memory=8192
    sapiadm update $moray_svc params.max_locked_memory=8192
    sapiadm update $moray_svc params.max_swap=16384
    moray_zone_uuid=$(vmadm lookup -1 state=running alias=~moray)
    vmadm update $moray_zone_uuid max_physical_memory=8192
    vmadm update $moray_zone_uuid max_locked_memory=8192
    vmadm update $moray_zone_uuid max_swap=16384
    # napi 1024
    sdc_app=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
    napi_svc=$(sdc-sapi /services?application_uuid=$sdc_app\&name=napi | json -H 0.uuid)
    sapiadm update $napi_svc params.max_physical_memory=1024
    sapiadm update $napi_svc params.max_locked_memory=1024
    sapiadm update $napi_svc params.max_swap=2048
    napi_zone_uuid=$(vmadm lookup -1 state=running alias=napi0)
    vmadm update $napi_zone_uuid max_physical_memory=1024
    vmadm update $napi_zone_uuid max_locked_memory=1024
    vmadm update $napi_zone_uuid max_swap=2048
    # amon 1024
    sdc_app=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
    amon_svc=$(sdc-sapi /services?application_uuid=$sdc_app\&name=amon | json -H 0.uuid)
    sapiadm update $amon_svc params.max_physical_memory=1024
    sapiadm update $amon_svc params.max_locked_memory=1024
    sapiadm update $amon_svc params.max_swap=2048
    amon_zone_uuid=$(vmadm lookup -1 state=running alias=amon0)
    vmadm update $amon_zone_uuid max_physical_memory=1024
    vmadm update $amon_zone_uuid max_locked_memory=1024
    vmadm update $amon_zone_uuid max_swap=2048
    # sdc 1024
    sdc_app=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
    sdc_svc=$(sdc-sapi /services?application_uuid=$sdc_app\&name=sdc | json -H 0.uuid)
    sapiadm update $sdc_svc params.max_physical_memory=1024
    sapiadm update $sdc_svc params.max_locked_memory=1024
    sapiadm update $sdc_svc params.max_swap=2048
    sdc_zone_uuid=$(vmadm lookup -1 state=running alias=sdc0)
    vmadm update $sdc_zone_uuid max_physical_memory=1024
    vmadm update $sdc_zone_uuid max_locked_memory=1024
    vmadm update $sdc_zone_uuid max_swap=2048
    # dhcpd 256
    sdc_app=$(sdc-sapi /applications?name=sdc | json -H 0.uuid)
    dhcpd_svc=$(sdc-sapi /services?application_uuid=$sdc_app\&name=dhcpd | json -H 0.uuid)
    sapiadm update $dhcpd_svc params.max_physical_memory=256
    sapiadm update $dhcpd_svc params.max_locked_memory=256
    sapiadm update $dhcpd_svc params.max_swap=512
    dhcpd_zone_uuid=$(vmadm lookup -1 state=running alias=dhcpd0)
    vmadm update $dhcpd_zone_uuid max_physical_memory=256
    vmadm update $dhcpd_zone_uuid max_locked_memory=256
    vmadm update $dhcpd_zone_uuid max_swap=512
fi

# -- HEAD-1958/HEAD-1961 region_name

grep region_name /usbkey/config >/dev/null 2>&1
if [ $? != 0 ]; then
    # Prompt for the region_name
    echo "A region name for this datacenter is required for upgrade."
    while [ -z "$region_name" ]; do
        echo -n "Enter region name: "
        read region_name

        echo -n "Is ${region_name} correct [y/N]? "
        read region_correct
        if [ "$region_correct" != "y" ]; then
            unset region_name
        fi
    done

    # Update the usbkey
    /usbkey/scripts/mount-usb.sh >/dev/null 2>&1
    if [ $? != 0 ]; then
        echo "Error: unable to mount the USB stick"
        exit 1
    fi

    cp /mnt/usbkey/config /tmp/config.$$
    echo "region_name=$region_name" >> /tmp/config.$$
    cp /tmp/config.$$ /mnt/usbkey/config

    # Update the usbkey cache
    cp -p /mnt/usbkey/config /usbkey/config

    umount /mnt/usbkey

    # Update SAPI
    sapi_sdc_uuid=$(sdc-sapi /applications?name=sdc | json -Ha uuid)
    if [ -z "$sapi_sdc_uuid" ]; then
        fatal "Unable to fetch the sapi application uuid."
    fi
    sapiadm update $sapi_sdc_uuid metadata.region_name=$region_name
    if [ $? != 0 ]; then
        fatal "Unable to update the sapi sdc application with $region_name."
    fi
fi
