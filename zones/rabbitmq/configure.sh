# We need rabbitmq running to be able to change any settings if it's OFF* that means
# it's still starting up, so we wait.
status=$(svcs -Ho STA svc:/application/rabbitmq:default)
while [[ ${status} == 'OFF*' ]]; do
    sleep 3
    status=$(svcs -Ho STA svc:/application/rabbitmq:default)
done

case ${status} in
    MNT)
        svcadm clear svc:/application/rabbitmq:default
    ;;
    OFF)
        svcadm enable -s svc:/application/rabbitmq:default
    ;;
    DIS)
        svcadm enable -s svc:/application/rabbitmq:default
    ;;
    ON)
        echo "Already running."
    ;;
    *)
        echo "Unhandled status: ${status}"
        exit 1
    ;;
esac

#
# On first boot at least, RabbitMQ pretends like it started up when it's not
# actually ready for us to use it yet.  In order to handle that case, we wait
# here for it to become ready before proceeding.  The last thing rabbitmq 2.3.1
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
        "/opt/local/sbin/rabbitmqctl -q -n rabbit@$(zonename) list_permissions -p /" \
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

# Add user, or if none specified: use guest
amqp_user=$(echo ${RABBITMQ} | cut -d':' -f1)
if [[ -z ${amqp_user} ]]; then
    amqp_user="guest"
    amqp_pass="guest"
else
    amqp_pass=$(echo ${RABBITMQ} | cut -d':' -f2)
fi

echo "Adding user ${amqp_user} and setting permissions"
su - rabbitmq -c "/opt/local/sbin/rabbitmqctl -n rabbit@$(zonename) add_user ${amqp_user} ${amqp_pass}"
su - rabbitmq -c "/opt/local/sbin/rabbitmqctl -n rabbit@$(zonename) set_admin ${amqp_user}"
su - rabbitmq -c "/opt/local/sbin/rabbitmqctl -n rabbit@$(zonename) set_permissions -p / ${amqp_user} \".*\" \".*\" \".*\""

