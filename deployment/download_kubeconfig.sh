#/bin/bash
set -euo pipefail

# Login information for Azure VM hosting Argo CD service.
server=${K3S_HOST}
admin_username=adminuser

# Default local kubeconfig directory.
kubeconfig_dir=${KUBECONFIG_DIR}

# AKS cluster info.
aks_rg_name=rg-pelleoapp
aks_cluster_name=aks-pelleoapp

# Repository information.
repo_name=distributed-az-edge-framework

# Get path to current script. Use below syntax rather than SCRIPTPATH=`pwd` 
# for proper handling of edge cases like spaces and symbolic links.  
script_path=$( cd -- $(dirname ${0}) >/dev/null 2>&1 ; pwd -P )
local_parent_dir=${script_path%%${repo_name}*}
local_repo_root=${local_parent_dir}/${repo_name}

# local_repo_root == GITHUB_WORKSPACE when using Git Actions ("control statement form").
[[ -z ${GITHUB_WORKSPACE+x} ]] || local_repo_root=${GITHUB_WORKSPACE} 

# File path of kubeconfig on remote K3s host
file_path=/home/${admin_username}/k3s-config

# Remove old entries from known hosts.
ssh-keygen -f ${HOME}/.ssh/known_hosts -R ${server}

# Monitor creation of k3s-config.
file_exists=no
n=24
for (( i=1; i<=n; i++ ))
do  
    echo 
    echo Checking if ${server}:${file_path} exists ${i} times out of ${n} ...
    echo 
    sleep 10
    
    # Test if there are containers still not ready
    file_exists=$(ssh -q -i ${local_repo_root}/local/.ssh/id_rsa \
        -o "StrictHostKeyChecking no" \
        ${admin_username}@${server} \
        [[ -f ${file_path} ]] && echo yes || echo no;)

    # Exit loop if file exists.
    [[ ${file_exists} == yes ]] && break
done

# Exit script if file not found.
if [[ ${file_exists} == no ]]; then
    echo File ${server}:${file_path} not found
    exit
fi

# File exists, download kubeconfig and node token from VM.
echo 
echo Downloading  ${server}:${file_path} to ${local_repo_root}/local ...
sleep 5
scp -i ${local_repo_root}/local/.ssh/id_rsa -o "StrictHostKeyChecking no" ${admin_username}@${server}:k3s-config ${local_repo_root}/local
scp -q -i ${local_repo_root}/local/.ssh/id_rsa -o "StrictHostKeyChecking no" ${admin_username}@${server}:node-token ${local_repo_root}/local

# WSL fix. Must copy the new kubeconfig to default WSL location.
echo 
echo Merging K3s demo cluster kubeconfig ...
file_path=${kubeconfig_dir}/config
[[ -f ${file_path} ]] && mv ${file_path} ${kubeconfig_dir}/config${RANDOM}.bak 
cp ${local_repo_root}/local/k3s-config ${file_path}

# Merge AKS cluster kubeconfig into default config store.
echo Merging AKS demo cluster kubeconfig ...
echo 
az aks get-credentials -g ${aks_rg_name} -n ${aks_cluster_name}