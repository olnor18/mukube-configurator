Configuration for what is needed to set up a HA that is part of a highly available control plane. Placed in the `config` file in the input directory.
```
NODE_CONTROL_PLANE_VIP=
NODE_CONTROL_PLANE_PORT=
MASTER_TAINT=
NODE_NETWORK_INTERFACES=
MASTER_VIP_CLUSTER_IPS=
MASTER_CERT_DIR=
NODE_JOIN_TOKEN=
MASTER_CERTIFICATE_KEY=
LB_IP_RANGE_START=
LB_IP_RANGE_STOP=
INGRESS_LB_IP_ADDRESS=
PROXY_ENABLED=
PROXY_SERVER=
PROXY_EXTERNAL_PROXY=
PROXY_CA_FILE=
KUBECONFIG_HOST=
KUBECONFIG_SSH_KEY=
REGISTRY_MIRRORS=
```

#### NODE_CONTROL_PLANE_VIP
The ip address of the control plane. If the first master node is being configured, this virtual ip will be created. 

#### NODE_CONTROL_PLANE_PORT
(Optional) The port where the control plane should listens on (default: `4200`).

#### MASTER_TAINT
Either true or false. If this master node should be tainted, meaning that no pods other than the static pods, will be scheduled to run here. Defaluts to true.

#### NODE_NETWORK_INTERFACES
(Optional) The names of the network interfaces where the devices are discoverable (default: `en*`).

#### MASTER_VIP_CLUSTER_IPS
A comma separated list of ips of all the master nodes.

### MASTER_VIP_CLUSTER_CIDR
Network subnet.

### WORKER_IPS 
A comma separated list of ips of all the worker nodes.

#### NODE_JOIN_TOKEN
A join token to use by other nodes joining the cluster. This is used to establish trust between the control plane and the joining nodes. Make sure the token is still valid.

#### MASTER_CERTIFICATE_KEY
A key used to encrypt the certificates.

### CLUSTER_DNS
The IP of the DNS server the cluster should use.

### LB_IP_RANGE_START
First IP address in the range to allocate for the load balancer.

### LB_IP_RANGE_STOP
Last IP address in the range to allocate for the load balancer.

### INGRESS_LB_IP_ADDRESS
Load balancer IP to allocate for the ingress.

### PROXY_ENABLED
(Optional) Configure CRI-O and Argo to use the HTTP proxy set by `HTTP_PROXY_SERVER` (default: `false`).

### PROXY_SERVER
(Optional) HTTP proxy which CRI-O and Argo should use (default: `http://nidhogg-lb-proxy.yggdrasil.svc.cluster.local:80`).

### PROXY_EXTERNAL_PROXY
(Required if `PROXY_ENABLED` is `true`) External proxy server to pass to the internal TCP loadbalancer, which CRI-O and Argo use by default.

### PROXY_CA_FILE
(Optional) Root certificate which CRI-O and Argo should trust when using the proxy.

### KUBECONFIG_HOST
(Optional) Host to transfer a `kubeconfig` file, with read only access to the cluster, to.

### KUBECONFIG_SSH_KEY
(Optional) SSH key to use for the transfer.

### REGISTRY_MIRRORS
(Optional) List of mirrors to configure in [`registries.conf.d`](https://github.com/containers/image/blob/70982d037a7a006fd3806dfb0882840aac2e2259/docs/containers-registries.conf.d.5.md), ex: `docker.io 192.168.1.10:5000 true,quay.io 192.168.1.20:5000 true` (`$registry $mirror $insecure`).

### Example file
```
NODE_CONTROL_PLANE_VIP=192.168.1.150
NODE_CONTROL_PLANE_PORT=4200
MASTER_TAINT=false
NODE_NETWORK_INTERFACES=eth0,eth0,eth0,ensp4,eth1
MASTER_VIP_CLUSTER_IPS=192.168.1.100,192.168.1.101,192.168.1.102,
MASTER_VIP_CLUSTER_CIDR=24
WORKER_IPS=192.168.1.110,192.168.1.111
NODE_GATEWAY_IP=192.168.1.1
LB_RANGE_START=192.168.1.20
LB_RANGE_STOP=192.168.1.30
INGRESS_LB_IP_ADDRESS=192.168.1.30
```
