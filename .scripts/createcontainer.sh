#!/bin/bash
# Usage ./createcontainer.sh <image name> <container name> [ip address] [network name]

# if the first or second arguments are missing give a usage message and exit
if [[ -z "$1" || -z "$2" ]]; then
    echo "Usage ./createcontainer.sh <image name> <container name> [ip address] [network name]"
    exit 1
else
    if [[ -z $(docker image ls -q $1) ]]; then
        # can't find the image, so exit
        echo "Image $1 does not exist"
        exit 1
    else
        IMAGE=$1
    fi

    NAME=$2
fi

# create a docker volume for storing data. this is automatically named after the container plus a suffix. 
DNSMASQ_DATA=${NAME}_dnsmasqdata && docker volume create $DNSMASQ_DATA
STUBBY_DATA=${NAME}_stubbydata && docker volume create $STUBBY_DATA

if [[ -z "$4" ]]; then 
    # network name not specified, default to bridge
    NETWORK="bridge" 
elif [[ -z $(docker network ls -f name=$4 -q) ]]; then
    # network name specified, but we can't find it, so exit
    echo "Network $4 does not exist"
    exit 1
else
    # passed all validation checks, good to go ahead ...
    NETWORK=$4
fi

IP=$3
if [[ -z "$3" ]]; then
    docker create --name "$NAME" \
        -P --network="$NETWORK" \
        -e TZ="Europe/London" \
        --restart=unless-stopped \
        --cap-add=NET_ADMIN \
        --mount type=volume,source=$DNSMASQ_DATA,target=/etc/dnsmasq.d \
        --mount type=volume,source=$STUBBY_DATA,target=/etc/stubby \
        "$IMAGE"
else
    docker create --name "$NAME" \
        -P --network="$NETWORK" --ip=$IP \
        -e TZ="Europe/London" \
        --restart=unless-stopped \
        --cap-add=NET_ADMIN \
        --mount type=volume,source=$DNSMASQ_DATA,target=/etc/dnsmasq.d \
        --mount type=volume,source=$STUBBY_DATA,target=/etc/stubby \
        "$IMAGE"
fi
# Note that the container already has a /etc/dnsmasq.d folder which contains files copied in during the image build.
# When I create the docker volume above and map it to the container, if this volume is empty the files from within the container are copied over to it.
# Subsequently the files from the volume are used in preference to the files in the image. 
# Ditto for /etc/stubby. 

# quit if the above step gave any error
[[ $? -ne 0 ]] && exit 1

printf "\nTo start the container do: \n\tdocker start $NAME"

printf "\n\nCreating ./${NAME}.service for systemd"
cat <<EOF > $NAME.service
[Unit]
Description=Stubby Unbound Container
Requires=docker.service
After=docker.service

[Service]
Restart=on-abort
ExecStart=/usr/bin/docker start -a $NAME
ExecStop=/usr/bin/docker stop -t 2 $NAME
ExecReload=/usr/bin/docker exec $NAME s6-svc -h /var/run/s6/services/dnsmasq

[Install]
WantedBy=local.target
EOF

printf "\n\nDo the following to install this in systemd & enable:"
printf "\n\tsudo cp ${NAME}.service /etc/systemd/system/"
printf "\n\tsudo systemctl enable ${NAME}.service"
printf "\n\nAnd if you want to start the service do: \n\tsudo systemctl start ${NAME}.service \n"
