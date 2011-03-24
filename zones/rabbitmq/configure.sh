
# We need rabbitmq running to be able to change any settings
status=$(svcs -Ho STA svc:/application/rabbitmq:default)
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

# Make sure we can actually talk to RabbitMQ
loops=0
while ! su - rabbitmq -c \
    "/opt/local/sbin/rabbitmqctl -n rabbit@rabbitmq -q list_vhosts" \
    >/dev/null 2>&1; do

    loops=$((${loops} + 1))
    if [[ ${loops} -gt 30 ]]; then
        echo "Rabbitmq timed out."
        exit 1
    fi
    sleep 1
done

# Even after we can list the vhosts, rabbit is still possibly not up!
# Check that we're also able to hit the overview page.
loops=0
while ! curl -i http://localhost:55672/api/overview; do
    loops=$((${loops} + 1))
    if [[ ${loops} -gt 30 ]]; then
        echo "Rabbitmq timed out."
        exit 1
    fi
    sleep 1
done

# Delete all the users
for user in $(su - rabbitmq -c \
    "/opt/local/sbin/rabbitmqctl -n rabbit@rabbitmq -q list_users" \
    | cut -d '	' -f1); do

    su - rabbitmq -c \
        "/opt/local/sbin/rabbitmqctl -n rabbit@rabbitmq delete_user ${user}"
done

# Double check that we really don't have any users
num_users=$(su - rabbitmq -c \
    "/opt/local/sbin/rabbitmqctl -n rabbit@rabbitmq -q list_users" | wc -l)

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
su - rabbitmq -c "/opt/local/sbin/rabbitmqctl -n rabbit@rabbitmq add_user ${amqp_user} ${amqp_pass}"
su - rabbitmq -c "/opt/local/sbin/rabbitmqctl -n rabbit@rabbitmq set_admin ${amqp_user}"
su - rabbitmq -c "/opt/local/sbin/rabbitmqctl -n rabbit@rabbitmq set_permissions -p / ${amqp_user} \".*\" \".*\" \".*\""

