SHELL := /bin/bash # Use bash syntax

# Set up variables
GO111MODULE=on
REGION ?= cn-northwest-1
IMAGE_REPOSITORY?=567711969428.dkr.ecr.cn-northwest-1.amazonaws.com.cn
IMG=${IMAGE_REPOSITORY}/unified-runtime/ack-s3-controller
TAG ?= v0.0.1
CRD_OPTIONS ?= "crd:trivialVersions=true"

# Build ldflags
VERSION ?= "v0.0.0"
GITCOMMIT=$(shell git rev-parse HEAD)
BUILDDATE=$(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
GO_LDFLAGS=-ldflags "-X main.version=$(VERSION) \
			-X main.buildHash=$(GITCOMMIT) \
			-X main.buildDate=$(BUILDDATE)"

.PHONY: all test local-test

all: test controller

# Build controller binary
controller: generate fmt vet
	go build -o bin/controller cmd/controller/main.go

# Run against the configured Kubernetes cluster in ~/.kube/config
run: generate fmt vet manifests
	go run ./cmd/controller/main.go

# Install CRDs into a cluster
install: manifests
	kustomize build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
uninstall: manifests
	kustomize build config/crd | kubectl delete -f -

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests
	cd config/controller && kustomize edit set image controller=${IMG}:${TAG}
	kustomize build config/default | kubectl apply -f -

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=controller-role paths="./..." output:crd:artifacts:config=config/crd/bases

# Run go fmt against code
fmt:
	go fmt ./...

# Run go vet against code
vet:
	go vet ./...

# Generate code
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

KUSTOMIZE = $(shell pwd)/bin/kustomize
kustomize: ## Download kustomize locally if necessary.
	$(call go-get-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v3@v3.8.7)

# Build the docker image
docker-build: test
	docker build . -t ${IMG}:${TAG}

# Push the docker image
docker-push:
	aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${IMAGE_REPOSITORY}
	docker push ${IMG}:${TAG}

# find or download controller-gen
# download controller-gen if necessary
controller-gen:
ifeq (, $(shell which controller-gen))
	@{ \
	set -e ;\
	CONTROLLER_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$CONTROLLER_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.2.5 ;\
	rm -rf $$CONTROLLER_GEN_TMP_DIR ;\
	}
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif


symlink:
	@ln -sfFn $(CWD)/pkg/version $(CWD)/version
	@ln -sfFn $(CWD)/pkg/resource $(CWD)/resource
	@ln -sfFn $(CWD)/apis/v1alpha1 $(CWD)/v1alpha1

test: generate fmt vet manifests ## Run code tests
	go test -v ./...

local-test: 		## Run code tests using go.local.mod file
	go test -modfile=go.local.mod -v ./...

help:           	## Show this help.
	@grep -F -h "##" $(MAKEFILE_LIST) | grep -F -v grep | sed -e 's/\\$$//' \
		| awk -F'[:#]' '{print $$1 = sprintf("%-30s", $$1), $$4}'
