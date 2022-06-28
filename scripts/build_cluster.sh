#!/bin/bash
NODEDIR=$1

OUTDIR=artifacts
mkdir -p $OUTDIR

# Pack every node
for node in $NODEDIR/*; do
	archive_path=$OUTDIR/$(basename $node).tar
	rm -f "${archive_path%%.tar}."*
	echo "[INFO] Archiving $node --> $archive_path"
	tar -cf $archive_path -C $node .

	tmp="$(mktemp -d)"
	cp "$archive_path" "$tmp/config.tar"
	mkfs.ext4 -L config -d "$tmp" "${archive_path%%.tar}.ext4" 1M
	rm -r "$tmp"
done
