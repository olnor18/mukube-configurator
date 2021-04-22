#!/bin/bash
DIR=$1
mkdir $DIR -p
cat helm_requirements | while read p; do
  echo $p 
  scripts/pack_single_helm_chart.sh $DIR ${p//%/ }
done

numberOfFiles=$(ls $DIR | wc -l)
linesInFile=$(grep -w ".*http.*" -c helm_requirements)

if [ $numberOfFiles != $linesInFile ]; then
    echo "[error] Helm charts download failed. 
          Numer of files in $DIR:$numberOfFiles does not equal the lines in helm requirements:$linesInFile"
    exit 1
fi
