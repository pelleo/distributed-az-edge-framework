#/bin/bash
set -euo pipefail

# Generate cloud-init input string.
CLOUD_INIT_STR=$(cat << EOSTR 
#cloud-config
package_update: true
package_upgrade: true
packages:
  - jq
output: {all: '| tee -a /var/log/cloud-init-output.log'}
runcmd:
  - curl ${RANCHER_DOCKER_INSTALL_URL} | sh
  - usermod -aG docker ${LINUX_ADMIN_USERNAME}
  - curl -sfL https://get.k3s.io | sh -s - server --tls-san ${HOST_IP_ADDRESS_OR_FQDN}
  - ufw allow 6443/tcp
  - ufw allow 443/tcp
  - cp /var/lib/rancher/k3s/server/node-token /home/${LINUX_ADMIN_USERNAME}/node-token
  - chown ${LINUX_ADMIN_USERNAME}:${LINUX_ADMIN_USERNAME} /home/${LINUX_ADMIN_USERNAME}/node-token
  - sed 's/127.0.0.1/${HOST_IP_ADDRESS_OR_FQDN}/g' /etc/rancher/k3s/k3s.yaml > /home/${LINUX_ADMIN_USERNAME}/k3s-config
  - chmod 600 /home/${LINUX_ADMIN_USERNAME}/k3s-config
  - chown ${LINUX_ADMIN_USERNAME}:${LINUX_ADMIN_USERNAME} /home/${LINUX_ADMIN_USERNAME}/k3s-config
  - wget -c https://get.helm.sh/${HELM_TAR_BALL} -P /home/${LINUX_ADMIN_USERNAME}
  - tar -xvf /home/${LINUX_ADMIN_USERNAME}/${HELM_TAR_BALL} --directory /home/${LINUX_ADMIN_USERNAME}
  - mv /home/${LINUX_ADMIN_USERNAME}/linux-amd64/helm /usr/local/bin/helm
  - helm repo add stable https://charts.helm.sh/stable
  - helm repo update
  - helm repo add argo https://argoproj.github.io/argo-helm
  - mkdir -p /home/${LINUX_ADMIN_USERNAME}/.kube
  - cp /etc/rancher/k3s/k3s.yaml /home/${LINUX_ADMIN_USERNAME}/.kube/config
  - kubectl create ns ${ARGOCD_NAMESPACE}
  - helm upgrade --kubeconfig /etc/rancher/k3s/k3s.yaml --install ${ARGOCD_RELEASE_NAME} argo/argo-cd --version ${ARGOCD_VERSION} -n ${ARGOCD_NAMESPACE}
  - rm -rf /home/${LINUX_ADMIN_USERNAME}/linux-amd64
  - chown -R ${LINUX_ADMIN_USERNAME}:${LINUX_ADMIN_USERNAME} /home/${LINUX_ADMIN_USERNAME}/.kube
  - chown ${LINUX_ADMIN_USERNAME}:${LINUX_ADMIN_USERNAME} /home/${LINUX_ADMIN_USERNAME}/${HELM_TAR_BALL}
  - curl -sSL -o /usr/local/bin/argocd ${ARGOCD_INSTALL_URL}
  - chmod 755 /usr/local/bin/argocd
final_message: >
    Open a web browser to access ArgoCD at http://${HOST_IP_ADDRESS_OR_FQDN}
EOSTR
)

# Double quotes around CLOUD_INIT_STR preserve newlines in stdout.  Required by cloud-init.
echo "${CLOUD_INIT_STR}" | base64 | tr -d '\n\r' | awk '{printf "{\"cloudInitFileAsBase64\": \"%s\"}", $1}' > ${AZ_SCRIPTS_OUTPUT_PATH}
