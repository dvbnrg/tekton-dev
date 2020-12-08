#!/usr/bin/env bash

# get creds from toolchain json

ARTIFACTORY_CREDS="$(cat /config/artifactory-dockerconfigjson | base64 -d)"
PASSWORD=$(echo $ARTIFACTORY_CREDS | jq -r '.[] | .[] | .password')
USERNAME=$(echo $ARTIFACTORY_CREDS | jq -r '.[] | .[] | .username')
COCOA_REGISTRY="na.artifactory.swg-devops.com/artifactory/api/npm/wcp-compliance-automation-team-npm-local"

#
# update .npmrc
#

echo "@cocoa:registry=https://${COCOA_REGISTRY}/" >> "$HOME/.npmrc"

curl -u "${USERNAME}:${PASSWORD}" https://na.artifactory.swg-devops.com/artifactory/api/npm/auth \
    | sed "s#^#//${COCOA_REGISTRY}/:#g" \
    >> "$HOME/.npmrc"

#
# install cocoa CLI
#

npm i -g @cocoa/scripts

#
# prepare data
#

export GHE_TOKEN="$(cat ../git-token)"
export COMMIT_SHA="$(cat /config/git-commit)"
export APP_NAME="$(cat /config/app-name)"

INVENTORY_REPO="$(cat /config/inventory-url)"
GHE_ORG=${INVENTORY_REPO%/*}
export GHE_ORG=${GHE_ORG##*/}
GHE_REPO=${INVENTORY_REPO##*/}
export GHE_REPO=${GHE_REPO%.git}

export APP_REPO="$(cat /config/repository-url)"
APP_REPO_ORG=${APP_REPO%/*}
export APP_REPO_ORG=${APP_REPO_ORG##*/}
APP_REPO_NAME=${APP_REPO##*/}
export APP_REPO_NAME=${APP_REPO_NAME%.git}

ARTIFACT="https://raw.github.ibm.com/${APP_REPO_ORG}/${APP_REPO_NAME}/${COMMIT_SHA}/deployment.yml"

#
# add to inventory
#

cocoa inventory add \
    --artifact="${ARTIFACT}" \
    --repository-url="${APP_REPO}" \
    --commit-sha="${COMMIT_SHA}" \
    --build-number="${BUILD_NUMBER}" \
    --pipeline-run-id="${PIPELINE_RUN_ID}" \
    --version="$(cat /config/version)" \
    --name="${APP_NAME}_deployment"
