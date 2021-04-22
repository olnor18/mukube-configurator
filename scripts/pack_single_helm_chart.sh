#!/bin/bash 
HELM_REQ_LINE=$1 
HELM_CHARTS_OUT_DIR=$2

echo "[INFO] packing: $HELM_REQ_LINE"
url=$(echo $HELM_REQ_LINE | cut -f1 -d' ')
release=$(echo $HELM_REQ_LINE | cut -f2 -d' ')
namespace=$(echo $HELM_REQ_LINE | cut -f3 -d' ')
filename=$(echo $url | rev | cut -f1 -d/ | rev)
# Download and rename file to include release and namespace
$(wget -O "$HELM_CHARTS_OUT_DIR/$release#$namespace#$filename" $url)
