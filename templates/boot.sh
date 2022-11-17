#!/bin/bash
# Load all the variables from the config.yaml file to variables
source mukube_init_config

case $NODE_TYPE in
    # guard clause for valid NODE_TYPE input
    master-init | master-join | worker) ;;
    *) echo "Invalid NODE_TYPE: $NODE_TYPE"; exit 1;;
esac

case $NODE_TYPE in
    *)
        # General setup
        hostname $NODE_NAME
        echo  "127.0.1.1	$NODE_NAME" >> /etc/hosts
        mount -o remount,size=$${ROOTFS_SIZE}G /
        ;;&
    master*)
        echo "MASTER NODE SETUP"
        if [ $IS_IN_AZURE == "true" ]; then
            /bin/bash /azure-health.sh
        fi

        # Activate the ip_vs kernel module to allow for load balancing. Required by Keepalived.
        modprobe ip_vs

        KUBERNETES_VERSION="$(kubeadm config print init-defaults | grep -m1 '^kubernetesVersion: ' | cut -f2 -d " ")"
        ;;& 
    master-init)
        echo "CREATING CLUSTER"
        echo "Bootstrapping virtual ip setup"
        mkdir -p /etc/kubernetes/manifests
        # If in Azure, then replace the "NODE_NETWORK_INTERFACE" variable in "keepalived.conf" with "vxlan0", else replace it with the network interfaces provided by the config
        if [ $IS_IN_AZURE == "true" ]; then
            sed "s/\$\$NODE_NETWORK_INTERFACE/vxlan0/" -i /etc/keepalived/keepalived.conf
        else
            sed "s/\$\$NODE_NETWORK_INTERFACE/$(basename /sys/class/net/$NODE_NETWORK_INTERFACE)/" -i /etc/keepalived/keepalived.conf
        fi
        sed "s/\$\$KUBERNETES_VERSION/$KUBERNETES_VERSION/" -i /etc/kubernetes/InitConfiguration.yaml
        mv /root/ha/* /etc/kubernetes/manifests
        init="kubeadm init --v=5 --config /etc/kubernetes/InitConfiguration.yaml --upload-certs" 
        printf "Creating cluster with command: \n\n\t $init \n\n"
        $init

        if [ -d /root/k8s ] && [ -n "$(ls -A /root/k8s)" ]; then
            until KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /root/k8s/; do
                sleep 1
            done
            kubeconfig="/tmp/admin-ro-$(date +%s).conf"
            kubeadm alpha kubeconfig user --client-name admin-ro --config /etc/kubernetes/InitConfiguration.yaml | grep -v "WARNING: port specified in controlPlaneEndpoint overrides" > "$kubeconfig"
            sftp -i /root/.ssh/kubeconfig-key.pub -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "$$KUBECONFIG_HOST" <<< "put \"$kubeconfig\""
            rm "$kubeconfig"
        fi
        ;;&
    master-join | worker)
        echo "JOINING CLUSTER"
        sed "s/\$\$KUBERNETES_VERSION/$KUBERNETES_VERSION/" -i /etc/kubernetes/JoinConfiguration.yaml
        init="kubeadm join --v=5 --config /etc/kubernetes/JoinConfiguration.yaml"
        printf "Joining cluster with command: \n\n\t $init \n\n"
        $init
        ;;&
    *) 
        # Error handling for kubeadm
        if (( $? != 0)); then echo "kubeadm failed"; exit 1; fi
        ;;&
    master-init)
        # Need to export KUBECONFIG for helm to contact the api-server
        export KUBECONFIG=/etc/kubernetes/admin.conf
        echo "Installing included helm charts"
        kubectl apply -f /root/crds.yaml
        for FILE in /root/manifest-*.yaml; do
            NAMESPACE="$(cut -f2- -d - <<< "$FILE" | cut -f1 -d .)"
            kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
            kubectl apply -n "$NAMESPACE" -f "$FILE"
        done
        ;;&
    master-join)
        echo "Joining virtual ip setup"
        if [ $IS_IN_AZURE == "true" ]; then
            sed "s/\$\$NODE_NETWORK_INTERFACE/vxlan0/" -i /etc/keepalived/keepalived.conf
        else
            sed "s/\$\$NODE_NETWORK_INTERFACE/$(basename /sys/class/net/$NODE_NETWORK_INTERFACE)/" -i /etc/keepalived/keepalived.conf
        fi
        mv /root/ha/* /etc/kubernetes/manifests
        ;;&
    master*)
        echo "Copy client etcd certs to /var/lib/etcdctl" 
        mkdir -p /var/lib/etcdctl 
        cp /etc/kubernetes/pki/etcd/server.crt /etc/kubernetes/pki/etcd/server.key /etc/kubernetes/pki/etcd/ca.crt /var/lib/etcdctl
        ;;&
esac
