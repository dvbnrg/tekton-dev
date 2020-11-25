#!/usr/bin/env bash

export IBMCLOUD_API_KEY
export IBMCLOUD_TOOLCHAIN_ID
export IBMCLOUD_IKS_REGION
export IBMCLOUD_IKS_CLUSTER_NAME
export IBMCLOUD_IKS_CLUSTER_NAMESPACE
export REGISTRY_URL
export IMAGE_PULL_SECRET_NAME
export IMAGE
export HOME
export BREAK_GLASS

if [ -f /config/api-key ]; then
  IBMCLOUD_API_KEY="$(cat /config/api-key)" # pragma: allowlist secret
else
  IBMCLOUD_API_KEY="$(cat /config/ibmcloud-api-key)" # pragma: allowlist secret
fi

HOME=/root
IBMCLOUD_TOOLCHAIN_ID="$(jq -r .toolchain_guid /toolchain/toolchain.json)"
IBMCLOUD_IKS_REGION="$(cat /config/dev-region | awk -F ":" '{print $NF}')"
IBMCLOUD_IKS_CLUSTER_NAMESPACE="$(cat /config/dev-cluster-namespace)"
IBMCLOUD_IKS_CLUSTER_NAME="$(cat /config/cluster-name)"
REGISTRY_URL="$(cat /config/image | awk -F/ '{print $1}')"
IMAGE="$(cat /config/image)"
IMAGE_PULL_SECRET_NAME="ibmcloud-toolchain-${IBMCLOUD_TOOLCHAIN_ID}-${REGISTRY_URL}"
BREAK_GLASS=$(cat /config/break_glass || echo false)

if [[ "$BREAK_GLASS" == true ]]; then
  export KUBECONFIG
  KUBECONFIG=/config/cluster-cert
else
  IBMCLOUD_IKS_REGION=$(echo "${IBMCLOUD_IKS_REGION}" | awk -F ":" '{print $NF}')
  ibmcloud login -r "$IBMCLOUD_IKS_REGION"
  eval "$(ibmcloud ks cluster config --cluster "$IBMCLOUD_IKS_CLUSTER_NAME" --export)"
fi
