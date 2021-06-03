WORKING_DIR=$1
TEMPLATES_DIR=$2

OUTPUT_DIR=$WORKING_DIR/etc/systemd/network

mkdir -p $OUTPUT_DIR

eval "cat <<EOF
$(<$TEMPLATES_DIR/10-systemd-network.network )
EOF
" > $OUTPUT_DIR/10-systemd-network.network

# # Configure the DNS by creating the resolved.conf 
# if [ $CLUSTER_DNS ]
# then
# eval "cat <<EOF
# $(<$TEMPLATES_DIR/resolved.conf)
# EOF
# " > $WORKING_DIR/etc/systemd/resolved.conf
# fi
# Configure the DNS by creating the resolved.conf 
if [ $CLUSTER_DNS ]
then
eval "cat <<EOF
$(<$TEMPLATES_DIR/resolv.conf)
EOF
" > $WORKING_DIR/etc/resolv.conf
fi
