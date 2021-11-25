#!/bin/bash
shopt -s extglob

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
        ;;&
    master*)
        echo "MASTER NODE SETUP"
        # Activate the ip_vs kernel module to allow for load balancing. Required by Keepalived.
        modprobe ip_vs
        ;;& 
    master-init)
        echo "CREATING CLUSTER"
        echo "Bootstrapping virtual ip setup"
        mkdir -p /etc/kubernetes/manifests
        sed "s/\$\$NODE_NETWORK_INTERFACE/$(basename /sys/class/net/$NODE_NETWORK_INTERFACE)/" -i /etc/keepalived/keepalived.conf
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
        for FILE in /root/helm-charts/!(values); do
            release=$(echo $FILE | cut -f4 -d/ | cut -f1 -d#)
            namespace=$(echo $FILE | cut -f4 -d/ | cut -f2 -d#)
            values_file="/root/helm-charts/values/$release.yaml"
            if [ -f "$values_file" ]; then
                helm install --create-namespace -f "$values_file" -n $namespace $release $FILE
            else
                helm install --create-namespace -n $namespace $release $FILE
            fi
        done
        ;;&
    master-join)
        echo "Joining virtual ip setup"
        sed "s/\$\$NODE_NETWORK_INTERFACE/$(basename /sys/class/net/$NODE_NETWORK_INTERFACE)/" -i /etc/keepalived/keepalived.conf
        mv /root/ha/* /etc/kubernetes/manifests
        ;;&
    master*)
        echo "Copy client etcd certs to /var/lib/etcdctl" 
        mkdir -p /var/lib/etcdctl 
        cp /etc/kubernetes/pki/etcd/server.crt /etc/kubernetes/pki/etcd/server.key /etc/kubernetes/pki/etcd/ca.crt /var/lib/etcdctl
        ;;&
esac
