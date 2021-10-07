#!/usr/bin/env bash

GITLAB_TOKEN=$(cat "$WORKSPACE/secrets/git-token")
GITLAB_URL="$(get_env SCM_API_URL)"
OWNER=$(jq -r '.services[] | select(.toolchain_binding.name=="app-repo") | .parameters.owner_id' /toolchain/toolchain.json)
REPO=$(jq -r '.services[] | select(.toolchain_binding.name=="app-repo") | .parameters.repo_name' /toolchain/toolchain.json)
curl --location --request PUT "${GITLAB_URL}/projects/${OWNER}%2F${REPO}/" \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --header 'Content-Type: application/json' \
    --data-raw '{
    "only_allow_merge_if_pipeline_succeeds": true
    }'