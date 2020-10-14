#!/usr/bin/bash

set -ex

export IBMCLOUD_API_KEY
export IBMCLOUD_IKS_REGION
export IBMCLOUD_IKS_CLUSTER_NAME
export IBMCLOUD_IKS_CLUSTER_NAMESPACE
export REGISTRY_URL
export IMAGE_PULL_SECRET_NAME
export IMAGE

IBMCLOUD_API_KEY="$(cat /config/api-key)" # pragma: allowlist secret

if [ -f /config/dev-region ]; then
  IBMCLOUD_IKS_REGION="$(cat /config/dev-region)"
  IBMCLOUD_IKS_CLUSTER_NAMESPACE="$(cat /config/dev-cluster-namespace)"
fi
IBMCLOUD_IKS_REGION=$(echo "${IBMCLOUD_IKS_REGION}" | awk -F ":" '{print $NF}')

IBMCLOUD_IKS_CLUSTER_NAME="$(cat /config/cluster-name)"
REGISTRY_URL="$(cat /config/image | awk -F/ '{print $1}')"
IMAGE="$REGISTRY_URL/$(cat /config/image | awk -F "/|@" '{print $2"/"$3"@"$4}')"
IMAGE_PULL_SECRET_NAME="ibmcloud-toolchain-${IBMCLOUD_TOOLCHAIN_ID}-${REGISTRY_URL}"
