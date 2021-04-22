#!/bin/bash 

echo $p
url=$(echo $p | cut -f1 -d' ')
release=$(echo $p | cut -f2 -d' ')
namespace=$(echo $p | cut -f3 -d' ')
filename=$(echo $url | rev | cut -f1 -d/ | rev)
# Download and rename file to include release and namespace
$(wget -O "$DIR/$release#$namespace#$filename" $url)
