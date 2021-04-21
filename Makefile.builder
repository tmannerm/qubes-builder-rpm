ifneq (,$(findstring fc,$(DIST)))
    DISTRIBUTION := fedora
else ifneq (,$(findstring centos-stream,$(DIST)))
    DISTRIBUTION := centos-stream
else ifneq (,$(findstring centos,$(DIST)))
    DISTRIBUTION := centos
endif

ifneq (,$(findstring $(DIST), leap tumbleweed))
    DISTRIBUTION := opensuse
    DIST_TAG := $(DIST)
endif

ifneq (,$(findstring $(DISTRIBUTION),fedora centos-stream centos opensuse))
    RPM_PLUGIN_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
    BUILDER_MAKEFILE = $(RPM_PLUGIN_DIR)Makefile.rpmbuilder
    TEMPLATE_SCRIPTS = $(RPM_PLUGIN_DIR)template_scripts
endif
