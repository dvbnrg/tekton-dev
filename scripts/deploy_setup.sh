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
export CLUSTER_INGRESS_SUBDOMAIN
export CLUSTER_INGRESS_SECRET
export DEPLOYMENT_FILE


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
BREAK_GLASS=$(cat /config/break_glass || echo "")
DEPLOYMENT_FILE="$(cat /config/deployment-file)"

if [ -z "${DEPLOYMENT_FILE}" ]; then
    echo "deployment-file environment is not defined. assuming deployment-file as deployment.yml"
    DEPLOYMENT_FILE=deployment.yml
fi


if [[ -n "${BREAK_GLASS}" ]]; then
  export KUBECONFIG
  KUBECONFIG=/config/cluster-cert
else
  IBMCLOUD_IKS_REGION=$(echo "${IBMCLOUD_IKS_REGION}" | awk -F ":" '{print $NF}')
  ibmcloud login -r "${IBMCLOUD_IKS_REGION}"
  ibmcloud ks cluster config --cluster "${IBMCLOUD_IKS_CLUSTER_NAME}"

  ibmcloud ks cluster get --cluster "${IBMCLOUD_IKS_CLUSTER_NAME}" --json > "${IBMCLOUD_IKS_CLUSTER_NAME}.json"

  # If the target cluster is openshift then make the appropriate additional login with oc tool
  if which oc > /dev/null && jq -e '.type=="openshift"' "${IBMCLOUD_IKS_CLUSTER_NAME}.json" > /dev/null; then
    echo "${IBMCLOUD_IKS_CLUSTER_NAME} is an openshift cluster. Doing the appropriate oc login to target it"
    oc login -u apikey -p "${IBMCLOUD_API_KEY}"
  fi
fi

CLUSTER_INGRESS_SUBDOMAIN=$( ibmcloud ks cluster get --cluster ${IBMCLOUD_IKS_CLUSTER_NAME} --json | jq -r '.ingressHostname // .ingress.hostname' | cut -d, -f1 )
CLUSTER_INGRESS_SECRET=$( ibmcloud ks cluster get --cluster ${IBMCLOUD_IKS_CLUSTER_NAME} --json | jq -r '.ingressSecretName // .ingress.secretName' | cut -d, -f1 )


if [ ! -z "${CLUSTER_INGRESS_SUBDOMAIN}" ] && [ "${KEEP_INGRESS_CUSTOM_DOMAIN}" != true ]; then
  echo "=========================================================="
  echo "UPDATING manifest with ingress information"
  INGRESS_DOC_INDEX=$(yq read --doc "*" --tojson $DEPLOYMENT_FILE | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="ingress") | .key')
  if [ -z "$INGRESS_DOC_INDEX" ]; then
    echo "No Kubernetes Ingress definition found in $DEPLOYMENT_FILE."
  else
    # Update ingress with cluster domain/secret information
    # Look for ingress rule whith host contains the token "cluster-ingress-subdomain"
    INGRESS_RULES_INDEX=$(yq r --doc $INGRESS_DOC_INDEX --tojson $DEPLOYMENT_FILE | jq '.spec.rules | to_entries | .[] | select( .value.host | contains("cluster-ingress-subdomain")) | .key')
    if [ ! -z "$INGRESS_RULES_INDEX" ]; then
      INGRESS_RULE_HOST=$(yq r --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE spec.rules[${INGRESS_RULES_INDEX}].host)
      yq w --inplace --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE spec.rules[${INGRESS_RULES_INDEX}].host ${INGRESS_RULE_HOST/cluster-ingress-subdomain/$CLUSTER_INGRESS_SUBDOMAIN}
    fi
    # Look for ingress tls whith secret contains the token "cluster-ingress-secret"
    INGRESS_TLS_INDEX=$(yq r --doc $INGRESS_DOC_INDEX --tojson $DEPLOYMENT_FILE | jq '.spec.tls | to_entries | .[] | select(.secretName="cluster-ingress-secret") | .key')
    if [ ! -z "$INGRESS_TLS_INDEX" ]; then
      yq w --inplace --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE spec.tls[${INGRESS_TLS_INDEX}].secretName $CLUSTER_INGRESS_SECRET
      INGRESS_TLS_HOST_INDEX=$(yq r --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE spec.tls[${INGRESS_TLS_INDEX}] --tojson | jq '.hosts | to_entries | .[] | select( .value | contains("cluster-ingress-subdomain")) | .key')
      if [ ! -z "$INGRESS_TLS_HOST_INDEX" ]; then
        INGRESS_TLS_HOST=$(yq r --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE spec.tls[${INGRESS_TLS_INDEX}].hosts[$INGRESS_TLS_HOST_INDEX])
        yq w --inplace --doc $INGRESS_DOC_INDEX $DEPLOYMENT_FILE spec.tls[${INGRESS_TLS_INDEX}].hosts[$INGRESS_TLS_HOST_INDEX] ${INGRESS_TLS_HOST/cluster-ingress-subdomain/$CLUSTER_INGRESS_SUBDOMAIN}
      fi
    fi
    if kubectl explain route > /dev/null 2>&1; then 
      if kubectl get secret ${CLUSTER_INGRESS_SECRET} --namespace=openshift-ingress; then
        if kubectl get secret ${CLUSTER_INGRESS_SECRET} --namespace ${IBMCLOUD_IKS_CLUSTER_NAMESPACE}; then 
          echo "TLS Secret exists in the ${IBMCLOUD_IKS_CLUSTER_NAMESPACE} namespace."
        else 
          echo "TLS Secret does not exists in the ${IBMCLOUD_IKS_CLUSTER_NAMESPACE} namespace. Copying from openshift-ingress."
          kubectl get secret ${CLUSTER_INGRESS_SECRET} --namespace=openshift-ingress -oyaml | grep -v '^\s*namespace:\s' | kubectl apply --namespace=${IBMCLOUD_IKS_CLUSTER_NAMESPACE} -f -
        fi
      fi
  
    fi
  fi
fi

