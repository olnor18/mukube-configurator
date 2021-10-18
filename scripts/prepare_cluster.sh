#!/bin/bash
OUTPUT_DIR=$1
VARIABLES=$2
source $VARIABLES

#TODO validate with regexp
if [ -z $MASTER_CERTIFICATE_KEY ]
then
    echo "[info] MASTER_CERTIFICATE_KEY not set. Generating new."
    MASTER_CERTIFICATE_KEY=$(docker run kubeadocker alpha certs certificate-key)
fi

#TODO validate with regexp
if [ -z $NODE_JOIN_TOKEN ]
then
    echo "[info] NODE_JOIN_TOKEN not set. Generating new. "
    NODE_JOIN_TOKEN=$(docker run kubeadocker token generate)
fi

if [ -z "$NODE_NETWORK_INTERFACES" ]
then
    echo "[error] NODE_NETWORK_INTERFACES required"
    exit 1
fi

if [ -z "$MASTER_VIP_CLUSTER_IPS" ]
then
    echo "[error] MASTER_VIP_CLUSTER_IPS required"
    exit 1
fi

if [ -z "$NODE_GATEWAY_IP" ]
then
    echo "[error] NODE_GATEWAY_IP required"
    exit 1
fi

if [ -z $CLUSTER_NAME ]
then
    echo "[INFO] CLUSTER_NAME not set. Using default: test"
    CLUSTER_NAME="test"
fi

# MAKE HOST_IP list
IFS=, read -ra MASTERS <<< "$MASTER_VIP_CLUSTER_IPS"
IFS=, read -ra WORKERS <<< "$WORKER_IPS"
IFS=, read -ra INTERFACES <<< "$NODE_NETWORK_INTERFACES"

total_nodes=$(expr ${#MASTERS[@]} + ${#WORKERS[@]})
total_interfaces=${#INTERFACES[@]}

if [ $total_nodes -ne $total_interfaces ]
then
    echo "[ERROR] Number of interfaces specified is not equal to the total number of masters and workers"
    exit 1
fi


# Export all variables for script scope
export NODE_JOIN_TOKEN=$NODE_JOIN_TOKEN
export MASTER_CERTIFICATE_KEY=$MASTER_CERTIFICATE_KEY
export MASTER_TAINT=$MASTER_TAINT
export NODE_GATEWAY_IP=$NODE_GATEWAY_IP
export CLUSTER_DNS=$CLUSTER_DNS
export CLUSTER_NAME=$CLUSTER_NAME

for ((i=0; i<${#MASTERS[@]}; i++)); do
    export NODE_NETWORK_INTERFACE=${INTERFACES[i]}
    export NODE_HOST_IP=${MASTERS[i]}
    export NODE_NAME=master$i
    export MASTER_PROXY_PRIORITY=$(expr 100 - $i)
    OUTPUT_DIR_MASTER=$OUTPUT_DIR/$CLUSTER_NAME-master$i

    if [ $i = 0 ];
    then
        export MASTER_PROXY_STATE=MASTER
        export NODE_TYPE=master-init
    else
        export MASTER_PROXY_STATE=BACKUP
        export NODE_TYPE=master-join
    fi

    OUTPUT_PATH_CONF=$OUTPUT_DIR_MASTER/mukube_init_config
    mkdir -p $OUTPUT_DIR_MASTER

    mkdir -p $OUTPUT_DIR_MASTER/etc/containers/
    cp templates/registries.conf $OUTPUT_DIR_MASTER/etc/containers/
    ./scripts/prepare_master_config.sh $OUTPUT_PATH_CONF $VARIABLES
    ./scripts/prepare_systemd_network.sh $OUTPUT_DIR_MASTER templates
    ./scripts/prepare_master_HA.sh $OUTPUT_DIR_MASTER templates
    ./scripts/prepare_k8s_configs.sh $OUTPUT_DIR_MASTER templates
    cp templates/boot.sh $OUTPUT_DIR_MASTER
done

# Prepare the worker nodes
export NODE_TYPE=worker
for ((i=0; i<${#WORKERS[@]}; i++)); do
    number_of_masters=${#MASTERS[@]}
    interface_index=$(expr $i + $number_of_masters)
    export NODE_NETWORK_INTERFACE=${INTERFACES[interface_index]}
    export NODE_HOST_IP=${WORKERS[i]}
    export NODE_NAME=worker$i

    OUTPUT_DIR_WORKER=$OUTPUT_DIR/$CLUSTER_NAME-worker$i
    mkdir -p $OUTPUT_DIR_WORKER

    mkdir -p $OUTPUT_DIR_WORKER/etc/containers/
    cp templates/registries.conf $OUTPUT_DIR_WORKER/etc/containers/
    cp templates/boot.sh $OUTPUT_DIR_WORKER
    ./scripts/prepare_node_config.sh $OUTPUT_DIR_WORKER/mukube_init_config $VARIABLES
    ./scripts/prepare_systemd_network.sh $OUTPUT_DIR_WORKER templates
    ./scripts/prepare_k8s_configs.sh $OUTPUT_DIR_WORKER templates
done
