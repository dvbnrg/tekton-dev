#!/usr/bin/bash

set -ex
IBMCLOUD_IKS_REGION=$(echo "${IBMCLOUD_IKS_REGION}" | awk -F ":" '{print $NF}')
ibmcloud login -r "$IBMCLOUD_IKS_REGION"
eval "$(ibmcloud ks cluster config --cluster "$IBMCLOUD_IKS_CLUSTER_NAME" --export)"

if kubectl get namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE"; then
  echo "Namespace ${IBMCLOUD_IKS_CLUSTER_NAMESPACE} found!"
else
  kubectl create namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE";
fi

if kubectl get secret -n "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" "$IMAGE_PULL_SECRET_NAME"; then
  echo "Image pull secret ${IMAGE_PULL_SECRET_NAME} found!"
else
  kubectl create secret docker-registry \
    --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" \
    --docker-server "$REGISTRY_URL" \
    --docker-password "$IBMCLOUD_API_KEY" \
    --docker-username iamapikey \
    --docker-email ibm@example.com \
    "$IMAGE_PULL_SECRET_NAME"

  kubectl patch serviceaccount \
    --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" \
    --patch '{"imagePullSecrets":[{"name":"'"$IMAGE_PULL_SECRET_NAME"'"}]}' \
    default
fi

sed -i "s~^\([[:blank:]]*\)image:.*$~\1image: ${IMAGE}~" deployment.yml

deployment_name=$(yq r deployment.yml metadata.name)
service_name=$(yq r -d1 deployment.yml metadata.name)

kubectl apply --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" -f deployment.yml
if kubectl rollout status --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" "deployment/$deployment_name"; then
  status=success
else
  status=failure
fi

kubectl get events --sort-by=.metadata.creationTimestamp -n "$IBMCLOUD_IKS_CLUSTER_NAMESPACE"

if [ "$status" = failure ]; then
  echo "Deployment failed"
  ibmcloud cr quota
  exit 1
fi

IP_ADDRESS=$(ibmcloud ks workers --cluster "$IBMCLOUD_IKS_CLUSTER_NAME" --json | jq -r '[.[] | select(.state=="normal")][0].publicIP')
PORT=$(kubectl get service -n  "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" "$service_name" -o json | jq -r '.spec.ports[0].nodePort')

echo "Application URL: http://${IP_ADDRESS}:${PORT}"

echo -n "http://${IP_ADDRESS}:${PORT}" > ../app-url
