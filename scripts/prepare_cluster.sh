#!/bin/bash
set -e
shopt -s extglob
OUTPUT_DIR=$1
VARIABLES=$2
source $VARIABLES

#TODO validate with regexp
if [ -z $MASTER_CERTIFICATE_KEY ]
then
    echo "[info] MASTER_CERTIFICATE_KEY not set. Generating new."
    # https://github.com/kubernetes/kubernetes/blob/cde45fb161c5a4bfa7cfe45dfd814f6cc95433f7/cmd/kubeadm/app/phases/copycerts/copycerts.go#L80-L87
    MASTER_CERTIFICATE_KEY=$(hexdump -e '"%x"' /dev/random | head -c64)
fi

#TODO validate with regexp
if [ -z $NODE_JOIN_TOKEN ]
then
    echo "[info] NODE_JOIN_TOKEN not set. Generating new. "
    # https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-token/#synopsis
    NODE_JOIN_TOKEN=$(tr -dc 'a-z0-9' < /dev/random | head -c 23 | sed s/././7)
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
FLUX_GIT_BRANCH=${FLUX_GIT_BRANCH:-main}
FLUX_PATH=${FLUX_PATH:-clusters/my-cluster/flux-system}
ROOTFS_SIZE=${ROOTFS_SIZE:-20}

AZURE_VXLAN_IPRANGE=${AZURE_VXLAN_IPRANGE:-10.2.0.0/24}

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

template_cluster_vars() {
    local -n vars="$1"
    args=()
    for var in "${!vars[@]}"; do
        args+=("--from-literal=$var=${vars[$var]}")
    done
    echo ---
    kubectl create "${@:2}" cluster-vars \
        --namespace=flux-system \
        "${args[@]}" \
        --dry-run=client \
        --output=yaml
}

for ((i=0; i<${#MASTERS[@]}; i++)); do
    export NODE_NETWORK_INTERFACE=${INTERFACES[i]:-en*}
    export NODE_HOST_IP=${MASTERS[i]}
    export NODE_NAME=master$i
    export MASTER_PROXY_PRIORITY=$(expr 100 - $i)
    OUTPUT_DIR_MASTER=$OUTPUT_DIR/$CLUSTER_NAME-master$i
    mkdir -p $OUTPUT_DIR_MASTER

    if [ $i = 0 ];
    then
        export MASTER_PROXY_STATE=MASTER
        export NODE_TYPE=master-init
    else
        export MASTER_PROXY_STATE=BACKUP
        export NODE_TYPE=master-join
    fi

    OUTPUT_PATH_CONF=$OUTPUT_DIR_MASTER/mukube_init_config

    mkdir -p $OUTPUT_DIR_MASTER/etc/containers/registries.conf.d/
    cp templates/registries.conf $OUTPUT_DIR_MASTER/etc/containers/
    cp "$mirrors_conf" $OUTPUT_DIR_MASTER/etc/containers/registries.conf.d/mirrors.conf


    if [ "$PROXY_ENABLED" = "true" ]; then
        mkdir -p "$OUTPUT_DIR_MASTER/etc/default"
        cp "$crio_sysconfig" "$OUTPUT_DIR_MASTER/etc/default/crio"
        if [ -n "$PROXY_CA_FILE" ]; then
            mkdir -p "$OUTPUT_DIR_MASTER/etc/crio/ssl/"
            cp "$PROXY_CA_FILE" "$OUTPUT_DIR_MASTER/etc/crio/ssl/root.pem"
            chmod 444 "$OUTPUT_DIR_MASTER/etc/crio/ssl/root.pem"
        fi
    fi

    if [ $i = 0 ]; then
        OUTPUT_PATH_VALUES="$(mktemp -d)"
        trap "rm -r \"$OUTPUT_PATH_VALUES\"" EXIT
        mkdir -p "$OUTPUT_PATH_VALUES"

        GIT_DIR="build/$(sha256sum <<< "$FLUX_GIT_REPOSITORY$FLUX_GIT_BRANCH" | awk '{print $1}')"
        export GIT_SSH_COMMAND="ssh -o IdentitiesOnly=yes -F none -i \"$FLUX_SSH_KEY\""
        GIT_TRANSPORT_PROTOCOL="$(cut -f1 -d : <<< "$FLUX_GIT_REPOSITORY")"
        if [ -d "$GIT_DIR" ]; then
            git -C "$GIT_DIR" fetch
            git -C "$GIT_DIR" reset --hard "origin/$FLUX_GIT_BRANCH"
        else
            if [ -n "$FLUX_GIT_TOKEN" ] && ([ "$GIT_TRANSPORT_PROTOCOL" = "http" ] || [ "$GIT_TRANSPORT_PROTOCOL" = "https" ]); then
                FLUX_GIT_REPOSITORY="$(sed -E "s:^(http[s]?\://)(.*@)?:\1x-access-token\:$FLUX_GIT_TOKEN@:" <<< "$FLUX_GIT_REPOSITORY")"
            fi
            git clone --single-branch --branch "$FLUX_GIT_BRANCH" "$FLUX_GIT_REPOSITORY" "$GIT_DIR"
        fi
        unset GIT_SSH_COMMAND

        mkdir -p "$OUTPUT_DIR_MASTER/root"
        (cd "$GIT_DIR" && kubectl kustomize "$FLUX_PATH") > "$OUTPUT_DIR_MASTER/root/manifest-flux-system.yaml"
        echo --- >> "$OUTPUT_DIR_MASTER/root/manifest-flux-system.yaml"

        if [ "$GIT_TRANSPORT_PROTOCOL" = "ssh" ]; then
            GIT_SERVER="$(cut -f2 -d@ <<< "$FLUX_GIT_REPOSITORY" | cut -f1 -d : | cut -f1 -d /)"
            kubectl create secret generic flux-system \
                --namespace=flux-system \
                --from-file=identity="$FLUX_SSH_KEY" \
                --from-file=identity.pub=<(ssh-keygen -f "$FLUX_SSH_KEY" -y) \
                --from-file=known_hosts=<(ssh-keyscan $GIT_SERVER) \
                --dry-run=client \
                --output=yaml >> "$OUTPUT_DIR_MASTER/root/manifest-flux-system.yaml"
        elif [ "$GIT_TRANSPORT_PROTOCOL" = "http" ] || [ "$GIT_TRANSPORT_PROTOCOL" = "https" ]; then
            if [ -n "$FLUX_GIT_TOKEN" ]; then
                kubectl create secret generic flux-system \
                    --namespace=flux-system \
                    --from-literal=username=x-access-token \
                    --from-file=password=<(echo -n "$FLUX_GIT_TOKEN") \
                    --dry-run=client \
                    --output=yaml >> "$OUTPUT_DIR_MASTER/root/manifest-flux-system.yaml"
            fi
        else
            echo "Unknown Git transport protoctol: $GIT_TRANSPORT_PROTOCOL"
            exit 1
        fi

        declare -A cluster_vars # configmap
        declare -A cluster_vars_secret
        cluster_vars[lb_ip_range_start]="$LB_IP_RANGE_START"
        cluster_vars[lb_ip_range_stop]="$LB_IP_RANGE_STOP"

        mkdir -p "$OUTPUT_DIR_MASTER/root/"
        if [ -n "$VAULT_SERVER" ] && [ -n "$VAULT_ROLE_ID" ] && [ -n "$VAULT_SECRET_ID" ]; then
            cluster_vars[vault_server]="$VAULT_SERVER"
            cluster_vars[vault_role_id]="$VAULT_ROLE_ID"
            cluster_vars_secret[vault_secret_id]="$VAULT_SECRET_ID"
        fi
        if [ "$PROXY_ENABLED" = "true" ] && [ -n "$PROXY_CA_FILE" ]; then
            cluster_vars[proxy_server]="$PROXY_SERVER"
            cluster_vars[proxy_root_certificate]="$(<"$PROXY_CA_FILE")"
        elif [ "$FLUX_GIT_BRANCH" != "master" ] && [ "$FLUX_GIT_BRANCH" != "main" ]; then
            cluster_vars[branch]="$FLUX_GIT_BRANCH"
        fi
        template_cluster_vars cluster_vars configmap >> "$OUTPUT_DIR_MASTER/root/manifest-flux-system.yaml"
        template_cluster_vars cluster_vars_secret secret generic >> "$OUTPUT_DIR_MASTER/root/manifest-flux-system.yaml"
        yq e 'select(.kind == "CustomResourceDefinition")' "$OUTPUT_DIR_MASTER/root/manifest-flux-system.yaml" > "$OUTPUT_DIR_MASTER/root/crds.yaml"

        if [ -n "$FLUX_CILIUM_HELM_RELEASE" ]; then
            # TODO: Pull from HelmRepository manifest
            CILIUM_HELM_REPO="https://helm.cilium.io/"

            CHART="$(yq .spec.chart.spec.chart < "$GIT_DIR/$FLUX_CILIUM_HELM_RELEASE")"
            CHART_NAME="$(yq .metadata.name < "$GIT_DIR/$FLUX_CILIUM_HELM_RELEASE")"
            CHART_NAMESPACE="$(yq .metadata.namespace < "$GIT_DIR/$FLUX_CILIUM_HELM_RELEASE")"
            CHART_VERSION="$(yq .spec.chart.spec.version < "$GIT_DIR/$FLUX_CILIUM_HELM_RELEASE")"
            CHART_VALUES="$(yq .spec.values < "$GIT_DIR/$FLUX_CILIUM_HELM_RELEASE")"
            if [ "$CHART_VALUES" = "null" ]; then
                CHART_VALUES=""
            else
                # Don't enable any service monitors
                CHART_VALUES="$(yq -o json <<< "$CHART_VALUES" | jq 'del(.. | objects.serviceMonitor)' | yq -P)"
            fi

            helm template --repo "$CILIUM_HELM_REPO" --skip-tests --include-crds -f <(echo "$CHART_VALUES") --version "$CHART_VERSION" -n "$CHART_NAMESPACE" "$CHART_NAME" "$CHART" >> "$OUTPUT_DIR_MASTER/root/manifest-kube-system.yaml"
            # Add Helm "ownership" labels
            yq --inplace eval-all '. *= load("templates/cilium-helm-ownership.yaml")' "$OUTPUT_DIR_MASTER/root/manifest-kube-system.yaml"
        fi
        yq e 'select(.kind == "CustomResourceDefinition")' "$OUTPUT_DIR_MASTER/root/manifest-kube-system.yaml" >> "$OUTPUT_DIR_MASTER/root/crds.yaml"
    fi

    # Every node's VXLAN needs a unique IP range where the VIP of the k8s control plane is accessible.
    if [ $IS_IN_AZURE == "true" ]; then
        # Retrieve the last octet of the IP of the current node
        unique_fourth_octet=$(cut -d . -f 4 <<< "$NODE_HOST_IP")
        # Create a new IP range using every octet of AZURE_VXLAN_IPRANGE before the last ".", add a "." and the unique fourth octet from above.
        # Finally add a "/" and everything from AZURE_VXLAN_IPRANGE after the last "/". 
        # It should create a new unique (for each node) IP range for the "vxlan0.network" file created in "prepare_systemd_network.sh" script.  
        newrange=${AZURE_VXLAN_IPRANGE%.*}.$unique_fourth_octet/${AZURE_VXLAN_IPRANGE#*/}
        export VXLAN_IP=$newrange

        cp templates/azure-report-ready.sh $OUTPUT_DIR_MASTER
    fi

    ./scripts/prepare_master_config.sh $OUTPUT_PATH_CONF $VARIABLES
    ./scripts/prepare_systemd_network.sh $OUTPUT_DIR_MASTER templates $VARIABLES
    ./scripts/prepare_master_HA.sh $OUTPUT_DIR_MASTER templates
    ./scripts/prepare_k8s_configs.sh $OUTPUT_DIR_MASTER templates
    cp templates/boot.sh $OUTPUT_DIR_MASTER
    
    sed -e "s/\$\${ROOTFS_SIZE}/$ROOTFS_SIZE/" -i $OUTPUT_DIR_MASTER/boot.sh
    if [ -n "$KUBECONFIG_HOST" ]; then
        mkdir $OUTPUT_DIR_MASTER/root/k8s/ $OUTPUT_DIR_MASTER/root/.ssh
        cp templates/readonly.yaml $OUTPUT_DIR_MASTER/root/k8s/
        cp "$KUBECONFIG_SSH_KEY" $OUTPUT_DIR_MASTER/root/.ssh/kubeconfig-key.pub
        chmod 600 $OUTPUT_DIR_MASTER/root/.ssh/kubeconfig-key.pub
        sed -e "s/\$\$KUBECONFIG_HOST/$KUBECONFIG_HOST/" -i $OUTPUT_DIR_MASTER/boot.sh
    fi

    if [ -n "$SSH_PUB_KEYS_FILE" ]; then
        mkdir -p $OUTPUT_DIR_MASTER/root/.ssh
        if [ -f "input/$SSH_PUB_KEYS_FILE" ]; then
            cp "input/$SSH_PUB_KEYS_FILE" "$OUTPUT_DIR_MASTER/root/.ssh/authorized_keys"
        else
            cp "$SSH_PUB_KEYS_FILE" "$OUTPUT_DIR_MASTER/root/.ssh/authorized_keys"
        fi
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
        mkdir -p "$OUTPUT_DIR_WORKER/etc/default"
        cp "$crio_sysconfig" "$OUTPUT_DIR_WORKER/etc/default/crio"
        if [ -n "$PROXY_CA_FILE" ]; then
            mkdir -p "$OUTPUT_DIR_WORKER/etc/crio/ssl/"
            cp "$PROXY_CA_FILE" "$OUTPUT_DIR_WORKER/etc/crio/ssl/root.pem"
            chmod 444 "$OUTPUT_DIR_WORKER/etc/crio/ssl/root.pem"
        fi
    fi
    cp templates/boot.sh $OUTPUT_DIR_WORKER
    sed -e "s/\$\${ROOTFS_SIZE}/$ROOTFS_SIZE/" -i $OUTPUT_DIR_MASTER/boot.sh
    ./scripts/prepare_node_config.sh $OUTPUT_DIR_WORKER/mukube_init_config $VARIABLES
    ./scripts/prepare_systemd_network.sh $OUTPUT_DIR_WORKER templates
    ./scripts/prepare_k8s_configs.sh $OUTPUT_DIR_WORKER templates
done

rm "$crio_sysconfig" "$mirrors_conf"
