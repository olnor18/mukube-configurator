#!/bin/bash 
HELM_CHARTS_OUT_DIR=$1
URL=$2
RELEASE=$3 
NAMESPACE=$4

echo "[INFO] packing: $URL to $HELM_CHARTS_OUT_DIR"
filename=$(echo $URL | rev | cut -f1 -d/ | rev)
# Download and rename file to include release and namespace
$(wget --quiet --show-progress -O "$HELM_CHARTS_OUT_DIR/$RELEASE#$NAMESPACE#$filename" $URL)
