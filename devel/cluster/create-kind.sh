#!/usr/bin/env bash

# Copyright 2020 The cert-manager Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o nounset
set -o errexit
set -o pipefail

SCRIPT_ROOT=$(dirname "${BASH_SOURCE}")
source "${SCRIPT_ROOT}/../lib/lib.sh"
source "${SCRIPT_ROOT}/../cluster/kind_cluster_node_versions.sh"

setup_tools

# Require kind & kubectl available on PATH
check_tool kubectl

# Specifies which Kind binary to use, allows to override for older version
KIND_BIN="${KIND}"

# Compute the details of the kind image to use
export KIND_IMAGE_SHA=""

# NB: Kind cluster image digests are autogenerated by hack/update-kind-images.sh

if [[ "$K8S_VERSION" =~ 1\.18 ]] ; then
  KIND_IMAGE_SHA=$KIND_IMAGE_SHA_K8S_118
elif [[ "$K8S_VERSION" =~ 1\.19 ]] ; then
  KIND_IMAGE_SHA=$KIND_IMAGE_SHA_K8S_119
elif [[ "$K8S_VERSION" =~ 1\.20 ]] ; then
  KIND_IMAGE_SHA=$KIND_IMAGE_SHA_K8S_120
elif [[ "$K8S_VERSION" =~ 1\.21 ]] ; then
  KIND_IMAGE_SHA=$KIND_IMAGE_SHA_K8S_121
elif [[ "$K8S_VERSION" =~ 1\.22 ]] ; then
  KIND_IMAGE_SHA=$KIND_IMAGE_SHA_K8S_122
elif [[ "$K8S_VERSION" =~ 1\.23 ]]; then
  KIND_IMAGE_SHA="sha256:8c3e98c086ece02428518a474e752a9ed0bf51da0ee93a8e6c47ca0937d7904b"
  KIND_IMAGE_REPO="eu.gcr.io/jetstack-build-infra-images/kind"
else
  echo "Unrecognised/unsupported Kubernetes version '${K8S_VERSION}'! Aborting..."
  exit 1
fi

export KIND_IMAGE="${KIND_IMAGE_REPO}@${KIND_IMAGE_SHA}"
echo "kind image details:"
echo "  repo:    ${KIND_IMAGE_REPO}"
echo "  sha256:  ${KIND_IMAGE_SHA}"
echo "  version: ${K8S_VERSION}"

if $KIND_BIN get clusters | grep "^$KIND_CLUSTER_NAME\$" &>/dev/null; then
  echo "Existing cluster '$KIND_CLUSTER_NAME' found, skipping creating cluster..."
  exit 0
fi

# Create the kind cluster
$KIND_BIN create cluster \
  --config "${SCRIPT_ROOT}/config/v1beta2.yaml" \
  --image "${KIND_IMAGE}" \
  --name "${KIND_CLUSTER_NAME}"

# Get the current config
original_coredns_config=$(kubectl get -ogo-template='{{.data.Corefile}}' -n=kube-system configmap/coredns)
additional_coredns_config="$(printf 'example.com:53 {\n    forward . 10.0.0.16\n}\n')"
echo "Original CoreDNS config:"
echo "${original_coredns_config}"
# Patch it
fixed_coredns_config=$(
  printf '%s\n%s' "${original_coredns_config}" "${additional_coredns_config}"
)
echo "Patched CoreDNS config:"
echo "${fixed_coredns_config}"
kubectl create configmap -oyaml coredns --dry-run --from-literal=Corefile="${fixed_coredns_config}" | kubectl apply --namespace kube-system -f -
