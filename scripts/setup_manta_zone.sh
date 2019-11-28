#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2017, Joyent, Inc.
#

#
# setup_manta_zone.sh: bootstrap a manta deployment zone
#

# BASHSTYLED
export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace
set -o errexit
set -o pipefail


PATH=/opt/smartdc/bin:$PATH

ZONE_ALIAS=manta0


function fatal {
    echo "$(basename $0): fatal error: $*" >&2
    exit 1
}


function add_external_nic {
    local zone_uuid=$1
    local tmpfile=/tmp/update_nics.$$.json

    local num_nics
    num_nics=$(sdc-vmapi /vms/${zone_uuid} | json -H nics.length)
    if [[ ${num_nics} == 2 ]]; then
        return  # External NIC already present
    fi

    echo "Adding external NIC to ${zone_uuid}"

    echo "
    {
        \"networks\": [
            {
                \"name\": \"external\",
                \"primary\": true
            }
        ]
    }" > ${tmpfile}

    sdc-vmapi /vms/${zone_uuid}?action=add_nics -X POST \
        -d @${tmpfile} | sdc-waitforjob

    rm -f ${tmpffile}
}


function import_manta_image {
    local image_uuid
    local service_uuid
    local status
    local image_manifest
    local image_file

    image_uuid=$(sdc-sapi /services?name=manta | json -H 0.params.image_uuid)
    if [[ -z "$image_uuid" ]]; then
        fatal "the 'manta' SAPI service does not have a params.image_uuid set"
    fi

    service_uuid=$(sdc-sapi /services?name=manta | json -Ha uuid)

    status=$(sdc-imgapi /images/${image_uuid} | head -1 | awk '{print $2}')
    if [[ "${status}" == "404" ]]; then
        # IMGAPI doesn't have the image imported. Let's try to get it from
        # the USB key.
        # - In the new world, this is at "/usbkey/images/UUID.imgmanifest".
        image_manifest="/usbkey/images/$image_uuid.imgmanifest"
        image_file="/usbkey/images/$image_uuid.imgfile"

        # - In the old world, it is at
        #   "/usbkey/datasets/manta-deployment-*.imgmanifest".
        if [[ ! -f $image_manifest ]]; then
            image_manifest=$(ls -r1 \
                /usbkey/datasets/manta-deployment-*.imgmanifest 2>/dev/null \
                || true | head -n 1)
            image_file=$(ls -r1 \
                /usbkey/datasets/manta-deployment-*.gz 2>/dev/null \
                || true | head -n 1)
            if [[ ! -f "$image_manifest" ]]; then
                fatal "could not find manta-deployment image $image_uuid in" \
                    "/usbkey/images or /usbkey/datasets"
            elif [[ "$($JSON -f $image_manifest uuid)" != "$image_uuid" ]]; then
                fatal "latest /usbkey/datasets/manta-deployment-*" \
                    "($image_manifest) image is not the same UUID as the SAPI" \
                    "'manta' service params.image_uuid ($image_uuid)"
            fi
        fi

        sdc-imgadm import -m ${image_manifest} -f ${image_file}
    fi
}


function deploy_manta_zone {
    local service_uuid server_uuid
    service_uuid=$(sdc-sapi /services?name=manta | json -Ha uuid)
    server_uuid=$(sysinfo | json UUID)

    if [[ -z "$server_uuid" ]]; then
        fatal "could not find appropriate server_uuid"
    fi

    echo "
    {
        \"service_uuid\": \"${service_uuid}\",
        \"params\": {
            \"alias\": \"${ZONE_ALIAS}\",
            \"server_uuid\": \"${server_uuid}\"
        }
    }" | sapiadm provision
}


function enable_firewall {
    local zone_uuid=$1
    vmadm update ${zone_uuid} firewall_enabled=true
}


# Wait for /opt/smartdc/manta-deployment/etc/config.json to be written out
# by config-agent.
function wait_for_config_agent {
    local CONFIG_PATH=/opt/smartdc/manta-deployment/etc/config.json
    local MANTA_ZONE
    MANTA_ZONE=$(vmadm lookup -1 alias=${ZONE_ALIAS})
    echo "Wait up to a minute for config-agent to write '$CONFIG_PATH'."
    local ZONE_CONFIG_PATH=/zones/$MANTA_ZONE/root$CONFIG_PATH
    for i in {1..30}; do
        if [[ -f "$ZONE_CONFIG_PATH" ]]; then
            break
        fi
        sleep 2
    done
    if [[ ! -f "$ZONE_CONFIG_PATH" ]]; then
        fatal "Timeout waiting for '$ZONE_CONFIG_PATH' to be written."
    else
        echo "'$CONFIG_PATH' created in manta zone."
    fi
}


function wait_for_manta_zone {
    local zone_uuid=$1
    local state="unknown"
    for i in {1..60}; do
        state=$(vmadm lookup -j alias alias=${ZONE_ALIAS} | json -ga zone_state)
        if [[ "running" == "$state" ]]; then
            break
        fi
        sleep 1
    done
    if [[ "$state" != "running" ]]; then
        fatal "manta zone isn't running after reboot"
    else
        echo "manta zone running"
    fi
}


# Copy manta tools into the GZ from the manta zone
function copy_manta_tools {
    local zone_uuid=$1
    local target

    if [[ -n ${zone_uuid} ]]; then
        from_dir=/zones/${zone_uuid}/root/opt/smartdc/manta-deployment
        to_dir=/opt/smartdc/bin

        # remove any tools from a previous setup
        rm -f ${to_dir}/manta-login
        rm -f ${to_dir}/manta-adm
        rm -f ${to_dir}/manta-oneach

        mkdir -p /opt/smartdc/manta-deployment/log

        # While manta-login is a bash script and we could link it directly,
        # we are using a little wrapper to avoid permission issues on the GZ.
        cat <<EOF > ${to_dir}/manta-login
#!/bin/bash
exec ${from_dir}/bin/manta-login "\$@"
EOF
        chmod +x ${to_dir}/manta-login
        #
        # manta-adm and manta-oneach are node programs, so we must write little
        # wrappers that call the real version using the node delivered in the
        # manta zone.
        #
        cat <<-EOF > ${to_dir}/manta-adm
	#!/bin/bash
	exec ${from_dir}/build/node/bin/node ${from_dir}/bin/manta-adm "\$@"
	EOF
        chmod +x ${to_dir}/manta-adm

        cat <<-EOF > ${to_dir}/manta-oneach
	#!/bin/bash
	exec ${from_dir}/build/node/bin/node ${from_dir}/bin/manta-oneach "\$@"
	EOF
        chmod +x ${to_dir}/manta-oneach

        #
        # Install a symlink in the parallel "man" tree for each program that
        # doesn't already have one.
        #
        for manpage in ${from_dir}/man/man1/*; do
            #
            # If we're looking at a zone version that does not have manual
            # pages here, we'll get a bogus entry for "*"
            #
            if [[ ! -e $manpage ]]; then
                continue;
            fi

            target="${to_dir}/../man/man1/$(basename "$manpage")"
            if [[ -e $target ]]; then
                echo "skipping $manpage ($target already exists)"
                continue;
            fi

            echo "creating symlink \"$target\" for \"$manpage\""
            ln -fs "$manpage" "$target"
        done
    fi
}


# Mainline

manta_uuid=$(vmadm lookup -1 alias=${ZONE_ALIAS} || true)
if [[ -n ${manta_uuid} ]]; then
    echo "Manta zone already present: $manta_uuid ($ZONE_ALIAS)"
    copy_manta_tools ${manta_uuid}
    exit
fi

imgapi_uuid=$(vmadm lookup alias=imgapi0)
add_external_nic ${imgapi_uuid}
enable_firewall ${imgapi_uuid}

import_manta_image
deploy_manta_zone
wait_for_config_agent
manta_zone_uuid=$(vmadm lookup -1 alias=${ZONE_ALIAS})
add_external_nic ${manta_zone_uuid}
wait_for_manta_zone ${manta_zone_uuid}
enable_firewall ${manta_zone_uuid}
copy_manta_tools ${manta_zone_uuid}
