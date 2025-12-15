#!/usr/bin/bash

# Function to convert dependencies to a valid environment variables
sanitize_var_name() {
    echo "$1" | tr '-' '_' | tr '[:lower:]' '[:upper:]'
}
# Read in dependencies.json file
set_env_vars() {
    local json_file="$1"

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed. Please install jq to parse JSON."
        exit 1
    fi

    # Read each key-value pair from the JSON file
    while IFS='=' read -r key value; do
        # Sanitize the key to create a valid environment variable name
        env_var=$(sanitize_var_name "$key")

        # Set the environment variable without exporting it to current shell
        printf -v "$env_var" '%s' "$value"
    done < <(jq -r 'to_entries[] | .key + "=" + .value' "$json_file")
}

# Set environment variables from dependencies.json
set_env_vars "dependencies.json"

# export just the values that we care about into the current session
export ADDON_VERSION=$ADDON_PROVIDER
echo "Set ADDON_VERSION=$ADDON_PROVIDER"

export CAPO_PROVIDER_VERSION=$CLUSTER_API_PROVIDER_OPENSTACK
echo "Set CAPO_PROVIDER_VERSION=$CLUSTER_API_PROVIDER_OPENSTACK"

export CAPI_HELM_CHART_VERSION=$CLUSTER_CHART
echo "Set CAPI_HELM_CHART_VERSION=$CLUSTER_CHART"
