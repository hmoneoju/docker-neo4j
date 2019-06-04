SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
.SECONDEXPANSION:
.SECONDARY:

ifeq ($(origin .RECIPEPREFIX), undefined)
  $(error This Make does not support .RECIPEPREFIX. Please use GNU Make 4.0 or later)
endif
.RECIPEPREFIX = >

ifndef NEO4J_VERSION
  $(error NEO4J_VERSION is not set)
endif

NETWORK_CONTAINER := "network"
COMPOSE_NETWORK := "neo4jcomposetest_lan"

tarball = neo4j-$(1)-$(2)-unix.tar.gz
dist_site := http://dist.neo4j.org
series := $(shell echo "$(NEO4J_VERSION)" | sed -E 's/^([0-9]+\.[0-9]+)\..*/\1/')

all: out/community/.sentinel out/enterprise/.sentinel
.PHONY: all

test: tmp/.image-id-community tmp/.image-id-enterprise
> echo mvn test -Dimage=$$(cat tmp/.image-id-community) -Dedition=community -Dversion=$(NEO4J_VERSION)
> echo mvn test -Dimage=$$(cat tmp/.image-id-enterprise) -Dedition=enterprise -Dversion=$(NEO4J_VERSION)
.PHONY: test

local: tmp/.image-id-community tmp/.image-id-enterprise
.PHONY: local

package: package-community package-enterprise

package-community: tmp/.image-id-community
> mkdir -p out
> docker tag $$(cat $<) neo4j:$(NEO4J_VERSION)
> docker save neo4j:$(NEO4J_VERSION) > out/neo4j-community-$(NEO4J_VERSION)-docker-complete.tar

package-enterprise: tmp/.image-id-enterprise
> mkdir -p out
> docker tag $$(cat $<) neo4j-enterprise:$(NEO4J_VERSION)
> docker save neo4j-enterprise:$(NEO4J_VERSION) > out/neo4j-enterprise-$(NEO4J_VERSION)-docker-complete.tar

#out/%/.sentinel: tmp/image-%/.sentinel tmp/.tests-pass-%
#> mkdir -p $(@D)
#> cp -r $(<D)/* $(@D)
#> touch $@
#
#tmp/test-context/.sentinel: test/container/Dockerfile
#> rm -rf $(@D)
#> mkdir -p $(@D)
#> cp -r $(<D)/* $(@D)
#> touch $@
#
#tmp/.image-id-network-container: tmp/test-context/.sentinel
#> mkdir -p $(@D)
#> image=network-container
#> docker rmi $$image || true
#> docker build --tag=$$image $(<D)
#> echo -n $$image >$@

#tmp/.tests-pass-%: tmp/.image-id-% $(shell find test -name 'test-*') \
#	$(shell find test -name '*.yml') $(shell find test -name '*.sh') \
#	tmp/.image-id-network-container
#> mkdir -p $(@D)
#> image_id=$$(cat $<)
#> for test in $(filter test/test-%,$^); do
#>   echo "Running NETWORK_CONTAINER=$(NETWORK_CONTAINER)-"$*" \
#COMPOSE_NETWORK=$(COMPOSE_NETWORK) $${test} $${image_id} ${series} $*"
#>   NETWORK_CONTAINER=$(NETWORK_CONTAINER)-"$*" COMPOSE_NETWORK=$(COMPOSE_NETWORK) \
#"$${test}" "$${image_id}" "${series}" "$*"
#> done
#> touch $@

tmp/.image-id-%: tmp/local-context-%/.sentinel
> mkdir -p $(@D)
> image=test/$$RANDOM
> docker build --tag=$$image \
    --build-arg="NEO4J_URI=file:///tmp/$(call tarball,$*,$(NEO4J_VERSION))" \
    $(<D)
> echo -n $$image >$@

tmp/local-context-%/.sentinel: tmp/image-%/.sentinel in/$(call tarball,%,$(NEO4J_VERSION))
> rm -rf $(@D)
> mkdir -p $(@D)
> cp -r $(<D)/* $(@D)
> cp $(filter %.tar.gz,$^) $(@D)/local-package
> touch $@

tmp/image-%/.sentinel: docker-image-src/$(series)/Dockerfile docker-image-src/$(series)/docker-entrypoint.sh \
                       in/$(call tarball,%,$(NEO4J_VERSION))
> mkdir -p $(@D)
> cp $(filter %/docker-entrypoint.sh,$^) $(@D)/docker-entrypoint.sh
> sha=$$(shasum --algorithm=256 $(filter %.tar.gz,$^) | cut -d' ' -f1)
> <$(filter %/Dockerfile,$^) sed \
    -e "s|%%NEO4J_SHA%%|$${sha}|" \
    -e "s|%%NEO4J_TARBALL%%|$(call tarball,$*,$(NEO4J_VERSION))|" \
    -e "s|%%NEO4J_EDITION%%|$*|" \
    -e "s|%%NEO4J_DIST_SITE%%|$(dist_site)|" \
    >$(@D)/Dockerfile
> mkdir -p $(@D)/local-package
> touch $(@D)/local-package/.sentinel
> touch $@

#run = trapping-sigint \
#    docker run --publish 7474:7474 --publish 7687:7687 \
#    --env=NEO4J_ACCEPT_LICENSE_AGREEMENT=yes \
#    --env=NEO4J_AUTH=neo4j/foo --rm $$(cat $1)
#build-enterprise: tmp/.image-id-enterprise
#> @echo "Neo4j $(NEO4J_VERSION)-enterprise available as: $$(cat $<)"
#build-community: tmp/.image-id-community
#> @echo "Neo4j $(NEO4J_VERSION)-community available as: $$(cat $<)"
#run-enterprise: tmp/.image-id-enterprise
#> $(call run,$<)
#run-community: tmp/.image-id-community
#> $(call run,$<)
#test-enterprise: tmp/.tests-pass-enterprise
#test-community: tmp/.tests-pass-community
#.PHONY: run-enterprise run-community build-enterprise build-community test-enterprise test-community

fetch_tarball = curl --fail --silent --show-error --location --remote-name \
    $(dist_site)/$(call tarball,$(1),$(NEO4J_VERSION))

cache: in/neo4j-%-$(NEO4J_VERSION)-unix.tar.gz
.PHONY: cache

in/neo4j-community-$(NEO4J_VERSION)-unix.tar.gz:
> mkdir -p in
> cd in
> $(call fetch_tarball,community)

in/neo4j-enterprise-$(NEO4J_VERSION)-unix.tar.gz:
> mkdir -p in
> cd in
> $(call fetch_tarball,enterprise)

clean:
> rm -rf tmp
> rm -rf out
.PHONY: clean
