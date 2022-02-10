#!/bin/bash
set -e
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

# MAKE HOST_IP list
IFS=, read -ra MASTERS <<< "$MASTER_VIP_CLUSTER_IPS"
IFS=, read -ra WORKERS <<< "$WORKER_IPS"
IFS=, read -ra INTERFACES <<< "$NODE_NETWORK_INTERFACES"

total_nodes=$(expr ${#MASTERS[@]} + ${#WORKERS[@]})
total_interfaces=${#INTERFACES[@]}

if [ -n "$NODE_NETWORK_INTERFACES" ] && [ $total_nodes -ne $total_interfaces ]
then
    echo "[ERROR] Number of interfaces specified is not equal to the total number of masters and workers"
    exit 1
fi


# Export all variables for script scope
export NODE_JOIN_TOKEN=$NODE_JOIN_TOKEN
export MASTER_CERTIFICATE_KEY=$MASTER_CERTIFICATE_KEY
export MASTER_TAINT=$MASTER_TAINT
export NODE_GATEWAY_IP=$NODE_GATEWAY_IP
export NODE_CONTROL_PLANE_PORT="${NODE_CONTROL_PLANE_PORT:-4200}"
export CLUSTER_DNS=$CLUSTER_DNS
export CLUSTER_NAME="${CLUSTER_NAME:-default}"
export MASTER_VIP_CLUSTER_CIDR
export PROXY_ENABLED="${PROXY_ENABLED:-false}"
export PROXY_SERVER=${PROXY_SERVER:-http://nidhogg-lb-proxy.yggdrasil.svc.cluster.local:80}
export KUBECONFIG_HOST
export KUBECONFIG_SSH_KEY

crio_sysconfig="$(mktemp)"
cat <<EOF > "$crio_sysconfig"
http_proxy="$PROXY_SERVER"
https_proxy="$PROXY_SERVER"
EOF

mirrors_conf="$(mktemp)"
while IFS= read -r line; do
  registry="$(awk '{print $1}' <<< "$line")"
  mirror="$(awk '{print $2}' <<< "$line")"
  insecure="$(awk '{print $3}' <<< "$line")"
  # https://github.com/containers/image/blob/70982d037a7a006fd3806dfb0882840aac2e2259/docs/containers-registries.conf.5.md
  printf '[[registry]]\nlocation = "%s"\n[[registry.mirror]]\nlocation = "%s"\ninsecure = %s\n\n' "$registry" "$mirror" "$insecure" >> "$mirrors_conf"
done < <(tr ',' '\n' <<< "$REGISTRY_MIRRORS" | sed '/^[[:space:]]*$/d')

if [ -n "$PROXY_CA_FILE" ]; then
    echo SSL_CERT_FILE=/etc/crio/ssl/root.pem >> "$crio_sysconfig"
fi

for ((i=0; i<${#MASTERS[@]}; i++)); do
    export NODE_NETWORK_INTERFACE=${INTERFACES[i]:-en*}
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

    mkdir -p $OUTPUT_DIR_MASTER/etc/containers/registries.conf.d/
    cp templates/registries.conf $OUTPUT_DIR_MASTER/etc/containers/
    cp "$mirrors_conf" $OUTPUT_DIR_MASTER/etc/containers/registries.conf.d/mirrors.conf
    OUTPUT_PATH_VALUES="$OUTPUT_DIR_MASTER/root/helm-charts/values"
    mkdir -p "$OUTPUT_PATH_VALUES"
    eval "echo \"$(<templates/nidhogg-lb.yaml)\"" >> "$OUTPUT_PATH_VALUES/nidhogg.yaml"
    if [ "$PROXY_ENABLED" = "true" ]; then
        mkdir -p "$OUTPUT_DIR_MASTER/etc/sysconfig"
        cp "$crio_sysconfig" "$OUTPUT_DIR_MASTER/etc/sysconfig/crio"
        eval "echo \"$(<templates/nidhogg-proxy.yaml)\"" >> "$OUTPUT_PATH_VALUES/nidhogg.yaml"
        if [ -n "$PROXY_CA_FILE" ]; then
            mkdir -p "$OUTPUT_DIR_MASTER/etc/crio/ssl/"
            cp "$PROXY_CA_FILE" "$OUTPUT_DIR_MASTER/etc/crio/ssl/root.pem"
            chmod 444 "$OUTPUT_DIR_MASTER/etc/crio/ssl/root.pem"
            cat templates/nidhogg-proxy-ca.yaml >> "$OUTPUT_PATH_VALUES/nidhogg.yaml"
        fi
    fi
    OUTPUT_PATH_VALUES_OVERRIDE="$OUTPUT_DIR/../root/helm-charts/values/"
    if [ -f "$OUTPUT_PATH_VALUES_OVERRIDE/nidhogg.yaml" ]; then
        # https://github.com/mikefarah/yq
        # https://mikefarah.gitbook.io/yq/v/v4.x/operators/reduce#merge-all-yaml-files-together
        yq eval-all '. as $item ireduce ({}; . * $item )' "$OUTPUT_PATH_VALUES/nidhogg.yaml" "$OUTPUT_PATH_VALUES_OVERRIDE/nidhogg.yaml" > "$OUTPUT_PATH_VALUES/nidhogg.yaml.tmp"
        mv "$OUTPUT_PATH_VALUES/nidhogg.yaml"{.tmp,}
    fi
    ./scripts/prepare_master_config.sh $OUTPUT_PATH_CONF $VARIABLES
    ./scripts/prepare_systemd_network.sh $OUTPUT_DIR_MASTER templates
    ./scripts/prepare_master_HA.sh $OUTPUT_DIR_MASTER templates
    ./scripts/prepare_k8s_configs.sh $OUTPUT_DIR_MASTER templates
    cp templates/boot.sh $OUTPUT_DIR_MASTER
    if [ -n "$KUBECONFIG_HOST" ]; then
        mkdir $OUTPUT_DIR_MASTER/root/k8s/ $OUTPUT_DIR_MASTER/root/.ssh
        cp templates/readonly.yaml $OUTPUT_DIR_MASTER/root/k8s/
        cp "$KUBECONFIG_SSH_KEY" $OUTPUT_DIR_MASTER/root/.ssh/kubeconfig-key.pub
        chmod 600 $OUTPUT_DIR_MASTER/root/.ssh/kubeconfig-key.pub
        sed -e "s/\$\$KUBECONFIG_HOST/$KUBECONFIG_HOST/" -i $OUTPUT_DIR_MASTER/boot.sh
    fi
done

# Prepare the worker nodes
export NODE_TYPE=worker
for ((i=0; i<${#WORKERS[@]}; i++)); do
    number_of_masters=${#MASTERS[@]}
    interface_index=$(expr $i + $number_of_masters)
    export NODE_NETWORK_INTERFACE=${INTERFACES[interface_index]:-en*}
    export NODE_HOST_IP=${WORKERS[i]}
    export NODE_NAME=worker$i

    OUTPUT_DIR_WORKER=$OUTPUT_DIR/$CLUSTER_NAME-worker$i
    mkdir -p $OUTPUT_DIR_WORKER

    mkdir -p $OUTPUT_DIR_WORKER/etc/containers/registries.conf.d/
    cp templates/registries.conf $OUTPUT_DIR_WORKER/etc/containers/
    cp "$mirrors_conf" $OUTPUT_DIR_WORKER/etc/containers/registries.conf.d/mirrors.conf
    if [ "$PROXY_ENABLED" = "true" ]; then
        mkdir -p "$OUTPUT_DIR_WORKER/etc/sysconfig"
        cp "$crio_sysconfig" "$OUTPUT_DIR_WORKER/etc/sysconfig/crio"
        if [ -n "$PROXY_CA_FILE" ]; then
            mkdir -p "$OUTPUT_DIR_WORKER/etc/crio/ssl/"
            cp "$PROXY_CA_FILE" "$OUTPUT_DIR_WORKER/etc/crio/ssl/root.pem"
            chmod 444 "$OUTPUT_DIR_MASTER/etc/crio/ssl/root.pem"
        fi
    fi
    cp templates/boot.sh $OUTPUT_DIR_WORKER
    ./scripts/prepare_node_config.sh $OUTPUT_DIR_WORKER/mukube_init_config $VARIABLES
    ./scripts/prepare_systemd_network.sh $OUTPUT_DIR_WORKER templates
    ./scripts/prepare_k8s_configs.sh $OUTPUT_DIR_WORKER templates
done

rm "$crio_sysconfig" "$mirrors_conf"
