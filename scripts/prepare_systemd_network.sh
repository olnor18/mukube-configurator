WORKING_DIR=$1
TEMPLATES_DIR=$2
VARIABLES=$3
source $VARIABLES

OUTPUT_DIR=$WORKING_DIR/etc/systemd/network

mkdir -p $OUTPUT_DIR

eval "cat <<EOF
$(<$TEMPLATES_DIR/10-systemd-network.network )
EOF
" > $OUTPUT_DIR/10-systemd-network.network

# Configure the DNS by creating the resolv.conf
eval "cat <<EOF
$(<$TEMPLATES_DIR/resolv.conf)
EOF
" > $WORKING_DIR/etc/resolv.conf.kubelet

mkdir -p "$WORKING_DIR/etc/systemd/resolved.conf.d"

cp "$TEMPLATES_DIR/cluster.local.conf" "$WORKING_DIR/etc/systemd/resolved.conf.d/"

# If running in Azure, then create the two network files ".netdev" and ".network" required by the new VXLAN
if [ $IS_IN_AZURE == "true" ]; then
    IFS=, read -ra MASTERS <<< "$MASTER_VIP_CLUSTER_IPS"

    cp "$TEMPLATES_DIR/vxlan0.netdev" "$OUTPUT_DIR/vxlan0.netdev"

    echo "
[Match]
Name=vxlan0

[Network]
Address=$VXLAN_IP
" > $OUTPUT_DIR/vxlan0.network

    for ((i=0; i<${#MASTERS[@]}; i++)); do
        if [ ${MASTERS[i]} = $NODE_HOST_IP ]; then
            continue
        fi

        echo "
[BridgeFDB]
MACAddress=00:00:00:00:00:00
Destination=${MASTERS[i]}
" >> $OUTPUT_DIR/vxlan0.network
    done
fi
