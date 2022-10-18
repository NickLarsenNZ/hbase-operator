# =============
# This file is automatically generated from the templates in stackabletech/operator-templating
# DO NOT MANUALLY EDIT THIS FILE
# =============

# This script requires https://github.com/mikefarah/yq (not to be confused with https://github.com/kislyuk/yq)
# It is available from Nixpkgs as `yq-go` (`nix shell nixpkgs#yq-go`)
# This script also requires `jq` https://stedolan.github.io/jq/

.PHONY: docker chart-lint compile-chart

TAG    := $(shell git rev-parse --short HEAD)

VERSION := $(shell cargo metadata --format-version 1 | jq -r '.packages[] | select(.name=="stackable-hbase-operator") | .version')
IS_NIGHTLY := $(shell echo "${VERSION}" | grep -- '-nightly$$')
# When rendering docs we want to simplify the version number slightly, only rendering "nightly" for nightly branches
# (since we only render nightlies for the active development trunk anyway) and chopping off the semver patch version otherwise
DOCS_VERSION := $(if ${IS_NIGHTLY},nightly,$(shell echo "${VERSION}" | sed 's/^\([0-9]\+\.[0-9]\+\)\..*$$/\1/'))
export VERSION IS_NIGHTLY DOCS_VERSION

SHELL=/usr/bin/env bash -euo pipefail

render-readme:
	scripts/render_readme.sh

## Docker related targets
docker-build:
	docker build --force-rm --build-arg VERSION=${VERSION} -t "docker.stackable.tech/stackable/hbase-operator:${VERSION}" -f docker/Dockerfile .

docker-build-latest: docker-build
	docker tag "docker.stackable.tech/stackable/hbase-operator:${VERSION}" \
	           "docker.stackable.tech/stackable/hbase-operator:latest"

docker-publish:
	echo "${NEXUS_PASSWORD}" | docker login --username github --password-stdin docker.stackable.tech
	docker push --all-tags docker.stackable.tech/stackable/hbase-operator

docker: docker-build docker-publish

docker-release: docker-build-latest docker-publish

## Chart related targets
compile-chart: version crds config

chart-clean:
	rm -rf deploy/helm/hbase-operator/configs
	rm -rf deploy/helm/hbase-operator/crds

version:
	yq eval -i '.version = strenv(VERSION) | .appVersion = strenv(VERSION)' /dev/stdin < deploy/helm/hbase-operator/Chart.yaml
	yq eval -i '.version = strenv(DOCS_VERSION) | .prerelease = strenv(IS_NIGHTLY) != ""' /dev/stdin < docs/antora.yml

config:
	if [ -d "deploy/config-spec/" ]; then\
		mkdir -p deploy/helm/hbase-operator/configs;\
		cp -r deploy/config-spec/* deploy/helm/hbase-operator/configs;\
	fi

crds:
	mkdir -p deploy/helm/hbase-operator/crds
	cargo run --bin stackable-hbase-operator -- crd | yq eval '.metadata.annotations["helm.sh/resource-policy"]="keep"' - > deploy/helm/hbase-operator/crds/crds.yaml

chart-lint: compile-chart
	docker run -it -v $(shell pwd):/build/helm-charts -w /build/helm-charts quay.io/helmpack/chart-testing:v3.5.0  ct lint --config deploy/helm/ct.yaml

## Manifest related targets
clean-manifests:
	mkdir -p deploy/manifests
	rm -rf $$(find deploy/manifests -maxdepth 1 -mindepth 1 -not -name Kustomization)

generate-manifests: clean-manifests compile-chart
	./scripts/generate-manifests.sh

regenerate-charts: chart-clean clean-manifests compile-chart generate-manifests
