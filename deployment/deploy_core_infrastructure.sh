#!/bin/bash

# ------------------------------------------------------------
#  Copyright (c) Microsoft Corporation.  All rights reserved.
#  Licensed under the MIT License (MIT). See License.txt in the repo root for license information.
# ------------------------------------------------------------

function write_title() {

    local test=${1}

    [[ -z ${test} ]] ||  printf "\n%s\n" "=[ ${test} ]="

}

function usage() {
    cat << EOOPTS

    Usage: $(basename $0) [Options] args

        $(basename $0) deploys a default AKS cluster. 

    args:

        application_name   Name of application

    Options:
    
    -L  Azure region (westeurope)
    -h  Print this information

    See also:
        
        https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/overview

EOOPTS
}

################################################################
#
# Prerequisites
#
################################################################

set -eo pipefail

# Silently continue if env var does not exist.
local_repo_root=${GITHUB_WORKSPACE}
repo_name=distributed-az-edge-framework

# Use location of current script to get local repo root if not executed by GitHub build agents.
if [[ -z ${local_repo_root} ]]; then
    # Use below syntax rather than script_path=`pwd` for proper 
    # handling of edge cases like spaces and symbolic links.
    script_path="$(cd -- "$(dirname "${0}")" >/dev/null 2>&1; pwd -P)"
    local_repo_root=${script_path%${repo_name}*}${repo_name}
fi

work_dir=${local_repo_root}/deployment
cd ${work_dir}

################################################################
#
# Parse arguments and options
#
################################################################

while getopts ":L:h" opt; do
    case ${opt} in
        L)        
            location=${OPTARG}
            ;;
        h)
            usage
            exit
            ;;
        \?)
            echo "$(basename ${0}): invalid option: -${OPTARG}" >&2
            usage
            exit 1
            ;;
        :)
            echo "$(basename ${0}): option -${OPTARG} requires an argument" >&2
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

# Assign default values to unassigned options.
location=${location:=westeurope}

# One mandatory argument.
if [[ $# -eq 1 ]]; then 
    application_name=$1
else
    if [[ $# -eq 0 ]]; then
        echo "$(basename ${0}): incorrect number of arguments" >&2
    else
        echo "$(basename ${0}): incorrect number of arguments: '$@'" >&2
    fi
    usage
    exit 1
fi

################################################################
#
# Main body
#
################################################################

deployment_id=${RANDOM}

write_title "Start Deploying Core Infrastructure"
start_time=$(date +%s)

# ----- Deploy Bicep
write_title "Deploy Bicep files"
r=$(az deployment sub create --location ${location} \
        --template-file ./bicep/core-infrastructure.bicep --parameters applicationName=${application_name} \
        --name "dep-${deployment_id}" -o json)

echo $r | jq 

aks_cluster_name=$(echo ${r} | jq -r '.properties.outputs.aksName.value') 
aks_cluster_principal_id=$(echo ${r} | jq -r '.properties.outputs.clusterPrincipalID.value') 
resource_group_name=$(echo ${r} | jq -r '.properties.outputs.resourceGroupName.value') 

# ----- Get Cluster Credentials
write_title "Get AKS Credentials"
az aks get-credentials --admin --name $aks_cluster_name --resource-group $resource_group_name --overwrite-existing

# ----- Connect AKS to Arc -----
echo
echo "Installing Arc providers, they may take some time to finish."
echo
az feature register --namespace Microsoft.ContainerService --name AKS-ExtensionManager
az provider register --namespace Microsoft.ContainerService --wait
az provider register --namespace Microsoft.Kubernetes --wait
az provider register --namespace Microsoft.KubernetesConfiguration --wait
az provider register --namespace Microsoft.ExtendedLocation --wait

# TODO: Add wait loop here to complete the registration of above extensions.
az connectedk8s connect --name ${aks_cluster_name} --resource-group ${resource_group_name}

export RESOURCEGROUPNAME=${resource_group_name}
export AKSCLUSTERPRINCIPALID=${aks_cluster_principal_id}
export AKSCLUSTERNAME=${aks_cluster_name}

end_time=$(date +%s)
running_time=$((end_time-start_time))
echo
echo "Running time: ${running_time} s"
echo
