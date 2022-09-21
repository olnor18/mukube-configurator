CONFIG ?= input/config

default: $(CONFIG) 
	./scripts/prepare_cluster.sh build/nodes $(CONFIG)
	./scripts/build_cluster.sh build/nodes

help:
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

## clean: remove output from the build
clean:
	rm -rf artifacts build
