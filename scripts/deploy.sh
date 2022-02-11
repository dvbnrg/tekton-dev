#!/usr/bin/env bash

echo "Updating the namespace in the deployment file....."
NAMESPACE_DOC_INDEX=$(yq read --doc "*" --tojson ${DEPLOYMENT_FILE} | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="namespace") | .key')
yq w -d ${NAMESPACE_DOC_INDEX} ${DEPLOYMENT_FILE} metadata.name "${IBMCLOUD_IKS_CLUSTER_NAMESPACE}" > "${TEMP_DEPLOYMENT_FILE}"
mv "${TEMP_DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}"
yq write --inplace $DEPLOYMENT_FILE --doc "*" "metadata.namespace" "${IBMCLOUD_IKS_CLUSTER_NAMESPACE}"

echo "Updating Image Pull Secrets Name in the deployment file......"
SECRET_DOC_INDEX=$(yq read --doc "*" --tojson $DEPLOYMENT_FILE | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="secret") | .key')
yq write --doc ${SECRET_DOC_INDEX} ${DEPLOYMENT_FILE} "metadata.name" "${IMAGE_PULL_SECRET_NAME}" > "${TEMP_DEPLOYMENT_FILE}"
mv "${TEMP_DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}"

SERVICE_ACCOUNT_DOC_INDEX=$(yq read --doc "*" --tojson $DEPLOYMENT_FILE | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="serviceaccount") | .key')
yq write --doc ${SERVICE_ACCOUNT_DOC_INDEX} ${DEPLOYMENT_FILE} "imagePullSecrets[0].name" "${IMAGE_PULL_SECRET_NAME}" > "${TEMP_DEPLOYMENT_FILE}"
mv "${TEMP_DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}"


echo "Updating Image Pull Secrets in the deployment file......"
REGISTRY_AUTH=""
if [[ -n "$BREAK_GLASS" ]]; then
  REGISTRY_AUTH=$(jq .parameters.docker_config_json /config/artifactory)
else
  REGISTRY_AUTH=$(echo "{\"auths\":{\"${REGISTRY_URL}\":{\"auth\":\"$(echo -n iamapikey:${IBMCLOUD_API_KEY} | base64 -w 0)\",\"username\":\"iamapikey\",\"email\":\"iamapikey\",\"password\":\"${IBMCLOUD_API_KEY}\"}}}" | base64 -w 0)
fi

yq write --doc ${SECRET_DOC_INDEX} ${DEPLOYMENT_FILE} "data[.dockerconfigjson]" "${REGISTRY_AUTH}" > "${TEMP_DEPLOYMENT_FILE}"
mv "${TEMP_DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}"


#Portieris is not compatible with image name containing both tag and sha. Removing the tag
IMAGE="${IMAGE#*"@"}"
sed -i "s~^\([[:blank:]]*\)image:.*$~\1image: ${IMAGE}~" ${DEPLOYMENT_FILE}

DEPLOYMENT_DOC_INDEX=$(yq read --doc "*" --tojson $DEPLOYMENT_FILE | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="deployment") | .key')
SERVICE_DOC_INDEX=$(yq read --doc "*" --tojson $DEPLOYMENT_FILE | jq -r 'to_entries | .[] | select(.value.spec.type=="NodePort" ) | .key')

deployment_name=$(yq r -d ${DEPLOYMENT_DOC_INDEX} ${DEPLOYMENT_FILE} metadata.name)
service_name=$(yq r -d ${SERVICE_DOC_INDEX} ${DEPLOYMENT_FILE} metadata.name)

kubectl apply --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" -f ${DEPLOYMENT_FILE}
if kubectl rollout status --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" "deployment/$deployment_name"; then
  status=success
else
  status=failure
fi

kubectl get events --sort-by=.metadata.creationTimestamp -n "$IBMCLOUD_IKS_CLUSTER_NAMESPACE"

if [ "$status" = failure ]; then
  echo "Deployment failed"
  if [[ -z "$BREAK_GLASS" ]]; then
    ibmcloud cr quota
  fi
  exit 1
fi
export APPURL
if [ "${CLUSTER_TYPE}" == "OPENSHIFT" ]; then
  ROUTE_DOC_INDEX=$(yq read --doc "*" --tojson $DEPLOYMENT_FILE | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="route") | .key')
  service_name=$(yq r --doc $ROUTE_DOC_INDEX $DEPLOYMENT_FILE metadata.name)
  APPURL=$(kubectl get route --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" "${service_name}" -o json | jq -r '.status.ingress[0].host')
  echo "Application URL: http://${APPURL}"
  echo -n http://${APPURL} >../app-url
else
  CLUSTER_INGRESS_SUBDOMAIN=$(ibmcloud ks cluster get --cluster ${IBMCLOUD_IKS_CLUSTER_NAME} --json | jq -r '.ingressHostname // .ingress.hostname' | cut -d, -f1)
  sleep 10
  if [ ! -z "${CLUSTER_INGRESS_SUBDOMAIN}" ] && [ "${KEEP_INGRESS_CUSTOM_DOMAIN}" != true ]; then
    INGRESS_DOC_INDEX=$(yq read --doc "*" --tojson $DEPLOYMENT_FILE | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="ingress") | .key')
    if [ -z "$INGRESS_DOC_INDEX" ]; then
      echo "No Kubernetes Ingress definition found in $DEPLOYMENT_FILE."
    else
      service_name=$(yq r --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE metadata.name)
      for ITER in {1..30}
      do
        APPURL=$(kubectl get ing ${service_name} --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" -o json | jq -r .status.loadBalancer.ingress[0].ip)
        if [ -z  "${APPURL}"  ]; then 
           echo "Waiting for the application url from ingress...."
           sleep 2
        else
          break
        fi
      done
      echo "Application URL: http://${APPURL}"
      echo -n http://${APPURL} >../app-url
      
    fi

  else

    IP_ADDRESS=$(kubectl get nodes -o json | jq -r '[.items[] | .status.addresses[] | select(.type == "ExternalIP") | .address] | .[0]')
    PORT=$(kubectl get service -n "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" "$service_name" -o json | jq -r '.spec.ports[0].nodePort')
    echo "Application URL: http://${IP_ADDRESS}:${PORT}"
    echo -n "http://${IP_ADDRESS}:${PORT}" >../app-url

  fi

fi
