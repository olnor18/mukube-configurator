Configuration for what is needed to set up a HA that is part of a highly available control plane. Placed in the `config` file in the root of the project.
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
```

#### NODE_CONTROL_PLANE_VIP
The ip address of the control plane. If the first master node is being configured, this virtual ip will be created. 

#### NODE_CONTROL_PLANE_PORT
The port where the control plane should listens on.

#### MASTER_TAINT
Either true or false. If this master node should be tainted, meaning that no pods other than the static pods, will be scheduled to run here. Defaluts to true.

#### NODE_NETWORK_INTERFACES
The names of the network interfaces where the devices are discoverable.

#### MASTER_VIP_CLUSTER_IPS
A comma separated list of ips of all the master nodes.

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

### Example file
```
NODE_CONTROL_PLANE_VIP=192.168.1.150
NODE_CONTROL_PLANE_PORT=4200
MASTER_TAINT=false
NODE_NETWORK_INTERFACES=eth0,eth0,eth0,ensp4,eth1
MASTER_VIP_CLUSTER_IPS=192.168.1.100,192.168.1.101,192.168.1.102,
WORKER_IPS=192.168.1.110,192.168.1.111
NODE_GATEWAY_IP=192.168.1.1
LB_RANGE_START=192.168.1.20
LB_RANGE_STOP=192.168.1.30
INGRESS_LB_IP_ADDRESS=192.168.1.30
```
