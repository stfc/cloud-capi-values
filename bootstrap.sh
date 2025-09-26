#!/usr/bin/env bash
set -euo pipefail

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

        # Set the environment variable
        export "$env_var"="$value"
        echo "Set $env_var=$value"
    done < <(jq -r 'to_entries[] | .key + "=" + .value' "$json_file")
}

# Set environment variables from dependencies.json
set_env_vars "dependencies.json"

# Check a clouds.yaml file exists in the same directory as the script
if [ ! -f clouds.yaml ]; then
    echo "A clouds.yaml file is required in the same directory as this script"
    exit 1
fi

echo "Updating system to apply latest security patches..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
# Shut apt up, since it just blows up the logs
sudo apt-get upgrade -y -qq > /dev/null

echo "Installing required tools..."
sudo apt-get install -y snapd python3-openstackclient
export PATH=$PATH:/snap/bin
sudo snap install kubectl --classic
sudo snap install helm --classic
sudo snap install yq

curl --no-progress-meter -L "https://github.com/kubernetes-sigs/cluster-api/releases/download/${CLUSTER_API}/clusterctl-linux-amd64" -o clusterctl
chmod +x clusterctl
sudo mv clusterctl /usr/local/bin/clusterctl

# Check that application_credential_id existing in clouds.yaml
# This has to be done after yq is installed
if [ "$(yq -r '.clouds.openstack.auth.application_credential_id' clouds.yaml)" == "null" ]; then
    # Enforce the use of app creds
    echo "Error: An app cred clouds.yaml file is required in the clouds.yaml file, normal creds (i.e. those with passwords) are not supported"
    exit 1
fi

if [ "$(yq -r '.clouds.openstack.auth.project_id' clouds.yaml)" == "null" ]; then
    echo "Looking up project_id for clouds.yaml..."
    APP_CRED_ID=$(yq -r '.clouds.openstack.auth.application_credential_id' clouds.yaml)
    PROJECT_ID=$(openstack --os-cloud openstack application credential show ${APP_CRED_ID} -c project_id -f value)
    echo "Injecting project ID: '${PROJECT_ID}' into clouds.yaml..."
    injected_id=$PROJECT_ID yq e '.clouds.openstack.auth.project_id = env(injected_id)' -i clouds.yaml
fi

echo "Installing and starting microk8s..."
sudo snap install microk8s --classic
sudo microk8s status --wait-ready

echo "Exporting the kubeconfig file..."
mkdir -p ~/.kube/
sudo microk8s.config  > ~/.kube/config
sudo chown $USER ~/.kube/config
sudo chmod 600 ~/.kube/config
sudo microk8s enable dns

echo "Initialising cluster-api OpenStack provider..."
echo "If this fails you may need a GITHUB_TOKEN, see https://stfc.atlassian.net/wiki/spaces/CLOUDKB/pages/211878034/Cluster+API+Setup for details"
clusterctl init --infrastructure=openstack:${CLUSTER_API_PROVIDER_OPENSTACK}

echo "Importing required helm repos and packages"
helm repo add capi https://azimuth-cloud.github.io/capi-helm-charts
helm repo add capi-addons https://azimuth-cloud.github.io/cluster-api-addon-provider
helm repo update
helm upgrade cluster-api-addon-provider capi-addons/cluster-api-addon-provider --create-namespace --install --wait -n clusters --version "${ADDON_PROVIDER}"

export ADDON_VERSION=$ADDON_PROVIDER
export CAPO_PROVIDER_VERSION=$CLUSTER_API_PROVIDER_OPENSTACK
export CAPI_HELM_CHART_VERSION=$CLUSTER_CHART

echo "You are now ready to create a cluster following the remaining instructions..."

echo "https://stfc.atlassian.net/wiki/spaces/CLOUDKB/pages/211878034/Cluster+API+Setup"
