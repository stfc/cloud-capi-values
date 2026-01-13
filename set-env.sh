#!/usr/bin/bash
set -euo pipefail

# Function to convert dependencies to a valid environment variables
sanitize_var_name() {
    echo "$1" | tr '-' '_' | tr '[:lower:]' '[:upper:]'
}
# Read in upstream dependencies.json file
set_env_vars() {
    local json_file="$1"

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed. Please install jq to parse JSON."
        exit 1
    fi

    # Read each key-value pair from the JSON file
    while IFS='=' read -r key value; do
        env_var=$(sanitize_var_name "$key")
        # Set the environment variable without exporting it to current shell
        printf -v "$env_var" '%s' "$value"
    done < <(jq -r 'to_entries[] | .key + "=" + .value' "$json_file")
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEP_FILE="${SCRIPT_DIR}/dependencies.yaml"
# Read our dependencies.yaml and export env variables 
if [[ -f "$DEP_FILE" ]]; then
  echo "Loading environment variables from $DEP_FILE"

  while IFS="=" read -r key value; do
    env_var=$(sanitize_var_name "$key")
    # Export all our dependencies
    echo "$env_var=$value"
    export "$env_var"="$value"
  done < <(yq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$DEP_FILE")
else
  echo "dependencies.yaml file not found: $DEP_FILE" >&2
  exit 1
fi

# Download upstream dependencies.json 
SOURCE_URL="https://raw.githubusercontent.com/azimuth-cloud/capi-helm-charts/refs/tags/${CLUSTER_CHART}/dependencies.json"
DEST_URL="/tmp/upstream_deps.json"

HTTP_STATUS=$(curl -s -w "%{http_code}" -o "$DEST_URL" "$SOURCE_URL")
if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "File downloaded successfully"
else
    echo "Failed to download file. HTTP status: $HTTP_STATUS"
    exit 1
fi

# Set environment variables from dependencies.json
set_env_vars "$DEST_URL"

# export just the values that we care about into the current session
export ADDON_VERSION=$ADDON_PROVIDER
echo "Set ADDON_VERSION=$ADDON_PROVIDER"

export CAPO_PROVIDER_VERSION=$CLUSTER_API_PROVIDER_OPENSTACK
echo "Set CAPO_PROVIDER_VERSION=$CLUSTER_API_PROVIDER_OPENSTACK"

export CAPI_HELM_CHART_VERSION=$CLUSTER_CHART
echo "Set CAPI_HELM_CHART_VERSION=$CLUSTER_CHART"


