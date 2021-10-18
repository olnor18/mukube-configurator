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
        mv /root/ha/* /etc/kubernetes/manifests
        init="kubeadm init --v=5 --config /etc/kubernetes/InitConfiguration.yaml --upload-certs" 
        printf "Creating cluster with command: \n\n\t $init \n\n"
        $init
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
        for FILE in /root/helm-charts/*; do
            release=$(echo $FILE | cut -f4 -d/ | cut -f1 -d#)
            namespace=$(echo $FILE | cut -f4 -d/ | cut -f2 -d#)
            helm install --create-namespace -n $namespace $release $FILE
        done
        ;;&
    master-join)
        echo "Joining virtual ip setup"
        mv /root/ha/* /etc/kubernetes/manifests
        ;;&
    master*)
        echo "Copy client etcd certs to /var/lib/etcdctl" 
        mkdir -p /var/lib/etcdctl 
        cp /etc/kubernetes/pki/etcd/server.crt /etc/kubernetes/pki/etcd/server.key /etc/kubernetes/pki/etcd/ca.crt /var/lib/etcdctl
        ;;&
esac
