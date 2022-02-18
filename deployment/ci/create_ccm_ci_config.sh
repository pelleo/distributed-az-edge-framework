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
  - curl -sfL https://get.k3s.io | sh -s - server --tls-san ${HOST_IP_ADDRESS_OR_FQDN} --write-kubeconfig-mode 644
  - ufw allow 6443/tcp
  - ufw allow 443/tcp
  - cp /var/lib/rancher/k3s/server/node-token /home/${LINUX_ADMIN_USERNAME}/node-token
  - chown ${LINUX_ADMIN_USERNAME}:${LINUX_ADMIN_USERNAME} /home/${LINUX_ADMIN_USERNAME}/node-token
  - sed 's/127.0.0.1/${HOST_IP_ADDRESS_OR_FQDN}/g' /etc/rancher/k3s/k3s.yaml > /home/${LINUX_ADMIN_USERNAME}/k3s-config
  - chmod 600 /home/${LINUX_ADMIN_USERNAME}/k3s-config
  - chown ${LINUX_ADMIN_USERNAME}:${LINUX_ADMIN_USERNAME} /home/${LINUX_ADMIN_USERNAME}/k3s-config
  - mkdir -p /home/${LINUX_ADMIN_USERNAME}/.kube
  - cp /etc/rancher/k3s/k3s.yaml /home/${LINUX_ADMIN_USERNAME}/.kube/config
  - chown -R ${LINUX_ADMIN_USERNAME}:${LINUX_ADMIN_USERNAME} /home/${LINUX_ADMIN_USERNAME}/.kube
  - mkdir -p /etc/kubernetes
  - chmod 777 /etc/kubernetes
  - mkdir -p /var/lib/waagent/ManagedIdentity-Settings
  - chmod 777 /var/lib/waagent/ManagedIdentity-Settings
EOSTR
)

# Double quotes around CLOUD_INIT_STR preserve newlines in stdout.  Required by cloud-init.
echo "${CLOUD_INIT_STR}" | base64 | tr -d '\n\r' | awk '{printf "{\"cloudInitFileAsBase64\": \"%s\"}", $1}' > ${AZ_SCRIPTS_OUTPUT_PATH}
