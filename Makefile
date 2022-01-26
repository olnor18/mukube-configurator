HELM_REQUIREMENTS ?= config/helm_requirements
CONFIG ?= config/config


default: $(CONFIG) pack-helm-charts
	./scripts/prepare_cluster.sh build/nodes $(CONFIG)
	./scripts/build_cluster.sh build/nodes

help:
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

HELM_DIR = build/root/helm-charts
# It is important that HELM_CHARTS is evaluated immediately ( := ) otherwise only the last helm package rule gets added
HELM_CHARTS := 

# Create make targets to download the helm packages specified in the HELM_REQUIREMENTS 
define DOWNLOAD_HELM_PACKAGE
release = $(shell echo $1 | cut -d % -f 1 )
namespace = $(shell echo $1 | cut -d % -f 2)
url = $(shell echo $1 | cut -d % -f 3- )
HELM_CHARTS += $(HELM_DIR)/$$(release)\#$$(namespace)\#$$(notdir $$(url))
$(HELM_DIR)/$$(release)\#$$(namespace)\#$$(notdir $$(url)) : $(HELM_DIR)/.empty
	curl -L $$(url) -o $$@ 
	[ -f "config/values/$$(release).yaml" ] && cp "config/values/$$(release).yaml" "$(HELM_DIR)/values/" || true
endef
$(foreach L,$(shell cat $(HELM_REQUIREMENTS)),$(eval $(call DOWNLOAD_HELM_PACKAGE,$L))) 

pack-helm-charts : $(HELM_DIR)/.empty $(HELM_CHARTS)
$(HELM_DIR)/.empty :
	mkdir -p $(@D) $(@D)/values && touch $@

## clean: remove output from the build
clean:
	rm -rf artifacts build
