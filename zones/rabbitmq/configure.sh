
# Delete all the users
for user in $(/opt/local/sbin/rabbitmqctl -n rabbit@rabbitmq -q list_users \
    | cut -d '	' -f1); do

    su - rabbitmq -c \
        "/opt/local/sbin/rabbitmqctl -n rabbit@rabbitmq delete_user ${user}"
done

# Add user, or if none specified: use guest
amqp_user=$(echo ${RABBITMQ} | cut -d':' -f1)
if [[ -z ${amqp_user} ]]; then
    amqp_user="guest"
    amqp_pass="guest"
else
    amqp_pass=$(echo ${RABBITMQ} | cut -d':' -f2)
fi

if [[ -z $(/usr/bin/svcs -a|grep rabbitmq) ]]; then
    echo "Starting rabbitmq"
    su - rabbitmq -c "/opt/local/sbin/rabbitmq-server -detached"
    sleep 10
fi

echo "Adding user ${amqp_user} and setting permissions"
su - rabbitmq -c "/opt/local/sbin/rabbitmqctl -n rabbit@rabbitmq add_user ${amqp_user} ${amqp_pass}"
su - rabbitmq -c "/opt/local/sbin/rabbitmqctl -n rabbit@rabbitmq set_permissions -p / ${amqp_user} \".*\" \".*\" \".*\""

if [[ -z $(/usr/bin/svcs -a|grep rabbitmq) ]]; then
  echo "User ${amqp_user} added. Stopping rabbitmq before importing the service"
  su - rabbitmq -c "/opt/local/sbin/rabbitmqctl -n rabbit@rabbitmq stop"

  echo "Importing rabbitmq service"
  /usr/sbin/svccfg import /opt/local/share/smf/manifest/rabbitmq.xml
  /usr/sbin/svcadm enable -s rabbitmq
fi

