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

        $(basename $0) deploys a cluster of one or more nodes 
        optionally behind a load balancer. 

    args:

        application_name   Name of application

    Options:
    
    -r  Azure region (westeurope)
    -l  Azure load balancer (no)
    -n  Number of cluster nodes (1)
    -u  Cloud-init script URI.  Must point to a public repository
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

while getopts ":r:l:n:u:h" opt; do
    case ${opt} in
        r)        
            location=${OPTARG}
            ;;
        l)        
            lb_deployment=${OPTARG}
            ;;
        n)
            vm_count=${OPTARG}
            ;;
        u)
            cloud_init_script_uri=${OPTARG}
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
lb_deployment=${lb_deployment:=no}
vm_count=${vm_count:=1}
cloud_init_script_uri=${cloud_init_script_uri:=https://raw.githubusercontent.com/pelleo/distributed-az-edge-framework/k3s/deployment/bicep/modules/create_cloud_init_input_string_bicep.sh}

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

write_title "Start Deploying Cluster Infrastructure"
start_time=$(date +%s)

# ----- Deploy Bicep
write_title "Deploy Bicep files"
r=$(az deployment sub create \
        --name "dep-${deployment_id}" -o json \
        --location ${location} \
        --template-file ./bicep/cluster-infrastructure.bicep \
        --parameters applicationName=${application_name} \
                     lbDeployment=${lb_deployment} \
                     vmCount=${vm_count} \
                     cloudInitScriptUri=${cloud_init_script_uri})

echo $r | jq 

# TODO:  modify
#k3s_cluster_name=$(echo ${r} | jq -r '.properties.outputs.aksName.value') 
#k3s_cluster_principal_id=$(echo ${r} | jq -r '.properties.outputs.clusterPrincipalID.value') 
resource_group_name=$(echo ${r} | jq -r '.properties.outputs.resourceGroupName.value')
cluster_fqdn=$(echo ${r} | jq -r '.properties.outputs.clusterFqdn.value')

# ----- TODO: modify
#write_title("Get K3s Credentials")
#az aks get-credentials --admin --name $k3s_cluster_name --resource-group $resource_group_name --overwrite-existing

# ----- Connect K3s to Arc -----
echo
echo "Installing Arc providers, they may take some time to finish."
echo
az feature register --namespace Microsoft.ContainerService --name AKS-ExtensionManager  # NEEDED ???
az provider register --namespace Microsoft.ContainerService --wait                      # NEEDED ???
az provider register --namespace Microsoft.Kubernetes --wait
az provider register --namespace Microsoft.KubernetesConfiguration --wait
az provider register --namespace Microsoft.ExtendedLocation --wait

# TODO: Add wait loop here to complete the registration of above extensions.
#az connectedk8s connect --name ${k3s_cluster_name} --resource-group ${resource_group_name}

#export RESOURCEGROUPNAME=${resource_group_name}
#export AKSCLUSTERPRINCIPALID=${k3s_cluster_principal_id}
#export AKSCLUSTERNAME=${k3s_cluster_name}

end_time=$(date +%s)
running_time=$((end_time-start_time))
echo
echo "Running time: ${running_time} s"
echo
