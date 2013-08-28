#!/bin/bash
#
# Copyright (c) 2011, 2012, Joyent Inc., All rights reserved.
#

export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
set -o xtrace

known_state=0
while [[ ${known_state} == 0 ]]; do
    status=$(svcs -Ho STA svc:/application/rabbitmq:default)
    case ${status} in
        MNT)
            svcadm clear svc:/application/rabbitmq:default
            known_state=1
        ;;
        OFF)
            svcadm enable -s svc:/application/rabbitmq:default
            known_state=1
        ;;
        DIS)
            svcadm enable -s svc:/application/rabbitmq:default
            known_state=1
        ;;
        ON)
            echo "Already running."
            known_state=1
        ;;
        *)
            # if rabbimq has a state that we can't handle, just wait until its
            # one we can, it'll either get there or this service will timeout
            # and go to maint.
            sleep 3
        ;;
    esac
done

#
# On first boot at least, RabbitMQ pretends like it started up when it's not
# actually ready for us to use it yet.  In order to handle that case, we wait
# here for it to become ready before proceeding.  The last thing rabbitmq 2.7.1
# does in the insert_default_data() function is:
#
#     rabbit_auth_backend_internal:set_permissions(...)
#
# So we're assuming here that when we see a list of permissions for this user
# that has completed.  If we see no users in this output eventually, that is an
# error anyway, because on first boot of the zone, guest should be created and
# this script should have deleted that guest and created the admin user on any
# other case.  If we wait 120 seconds and no users show up, we add ours anyway.
#

function list_permissions
{
    su - rabbitmq -c \
        "/opt/local/sbin/rabbitmqctl -q -n rabbit@$(zonename) list_user_permissions guest" \
        2>/dev/null \
    || /bin/true
}

waited=0
while [[ ${waited} -lt 120 && -z $(list_permissions) ]]; do
    sleep 2
    waited=$((${waited} + 2))
done

# Delete all the users
for user in $(su - rabbitmq -c \
    "/opt/local/sbin/rabbitmqctl -n rabbit@$(zonename) -q list_users" \
    | cut -d '	' -f1); do

    su - rabbitmq -c \
        "/opt/local/sbin/rabbitmqctl -n rabbit@$(zonename) delete_user ${user}"
done

# Double check that we really don't have any users
num_users=$(su - rabbitmq -c \
    "/opt/local/sbin/rabbitmqctl -n rabbit@$(zonename) -q list_users" | \
    wc -l | tr -d ' ')

if [[ ${num_users} != "0" ]]; then
    echo "Failed to remove users!"
    exit 1
fi

# XXX - break this up to natural fields.
sapi_metadata=/opt/smartdc/etc/sapi_metadata.json
amqp_config=$(json -f ${sapi_metadata} rabbitmq)
if [[ -n ${amqp_config} ]]; then
    amqp_user=$(echo ${amqp_config} | cut -d':' -f1)
    amqp_pass=$(echo ${amqp_config} | cut -d':' -f2)
fi
# rm ${sapi_metadata}

echo "Adding user ${amqp_user} and setting permissions"
su - rabbitmq -c "/opt/local/sbin/rabbitmqctl -n rabbit@$(zonename) add_user ${amqp_user} ${amqp_pass}"
su - rabbitmq -c "/opt/local/sbin/rabbitmqctl -n rabbit@$(zonename) set_user_tags ${amqp_user} administrator"
su - rabbitmq -c "/opt/local/sbin/rabbitmqctl -n rabbit@$(zonename) set_permissions -p / ${amqp_user} \".*\" \".*\" \".*\""

exit 0
