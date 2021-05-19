WORKING_DIR=$1
TEMPLATES_DIR=$2

CONF=$WORKING_DIR/mukube_init_config
OUTPUT_DIR=$WORKING_DIR/etc/kubernetes

source $CONF

mkdir -p $OUTPUT_DIR

case $NODE_TYPE in 
	master*)
		if [ $MASTER_TAINT == "true" ]
		then 
			export TAINT_MASTER_YAML=$'taints:\n  - effect: NoSchedule\n    key: node-role.kubernetes.io/master'
		else
			export TAINT_MASTER_YAML="taints: []"
		fi
	;;&
	master-init)
		eval "cat <<-EOF
			$(<$TEMPLATES_DIR/InitConfiguration.yaml )
			---
			$(<$TEMPLATES_DIR/ClusterConfiguration.yaml )
		EOF
		" > $OUTPUT_DIR/InitConfiguration.yaml
	;;
	master-join) 
		export CONTROL_PLANE_REGISTRATION=$'controlPlane:\n    certificateKey: '${MASTER_CERTIFICATE_KEY}$'\n    localAPIEndpoint:\n      advertiseAddress: '${NODE_HOST_IP}$'\n      bindPort: 6443'
	;;&
	worker)
		# NB: This value is never used. 
		export NODE_REGISTRATION="taints: []"
	;;&
	master-join | worker)
		eval "cat <<-EOF
			$(<$TEMPLATES_DIR/JoinConfiguration.yaml )
			---
			$(<$TEMPLATES_DIR/ClusterConfiguration.yaml )
		EOF
		" > $OUTPUT_DIR/JoinConfiguration.yaml
	;;
esac
