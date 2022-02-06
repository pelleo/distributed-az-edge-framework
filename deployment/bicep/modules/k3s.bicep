param location string
param environmentType string
param linuxAdminUsername string
//@secure()
param sshRSAPublicKey string

@description('URI for cloud init script executed by bicep script resource')
param cloudInitScriptUri string

@description('DNS prefix for load balancer incoming traffic')
param k3sDnsLabelPrefix string

@description('DNS prefix for load balancer outgoing traffic')
param k3sDnsLabelPrefixOutbound  string

@description('K3s cluster node name prefix')
param vmNamePrefix string 

@description('K3s cluster NIC prefix')
param  networkInterfaceNamePrefix string

@description('Number of virtual machines to be deployed.')
param vmCount int 

@description('Size of virtual machine.')
param vmSize string

@description('The name of the external load balancer')
param lbName string 

@minLength(3)
@maxLength(63)
@description('Name of file share.  Must be between 3 and 63 characters long.')
param fileShareName string

@allowed([
  'SMB'
  'NFS'
])
@description('Fileshare type.  Must be SMB or NFS.')
param fileShareType string

@description('Storage account prefix')
param storageAccountNamePrefix string

param tags object

@allowed([
  'yes'
  'no'
])
param lbDeployment string

@description('Name of network security group')
var nsgName = 'k3s-nsg'

@description('Name of virtual network')
var vnetName  = 'k3s-vnet'

@description('Address space of virtual network')
var vnetAddressPrefix = '10.1.0.0/16'

@description('Name of subnet')
var subnetName = 'k3s-snet'

@description('Address space of subnet prefix')
var subnetAddressPrefix  = '10.1.0.0/24'

@description('List of service endpoints to be enabled on subnet' )
var serviceEndpoints  = [
  {
    service: 'Microsoft.Storage'
  }
]

@description('Name of VM public IP resource')
var publicIPAddressName = '${vmNamePrefix}-public-ip'

@description('Name of load balancer public IP resource')
var publicIPAddressOutboundName = '${lbName}-public-ip'


@description('Name of load balancer frontent IP')
var lbFeAddressName = '${lbName}-fe-ip'

//@description('Name of load balancer outbound-frontent IP')
//var lbFeIPAddressOutboundName = '${lbName}-outbound-fe-ip'

@description('Name of load balancer backend pool')
var lbBePoolName = '${lbName}-be-pool'

//var lbBePoolNameOutbound = '${lbName}-outbound-be-pool'

var subnetRef = '${vnet.id}/subnets/${subnetName}'
var osDiskType = 'Standard_LRS'

@description('Disable password login and configure SSH')
var linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${linuxAdminUsername}/.ssh/authorized_keys'
        keyData: sshRSAPublicKey
      }
    ]
  }
}

var storageAccountSkuName = (environmentType == 'prod') ? 'Premium_ZRS' : 'Premium_LRS'
var resourceNameSuffix  = uniqueString(resourceGroup().id)
var storageAccountName = '${storageAccountNamePrefix}${resourceNameSuffix}'
var nfs =  (fileShareType == 'NFS') ? true : false
var domainNameLabel = '${k3sDnsLabelPrefix}-${resourceNameSuffix}'
var domainNameLabelOutbound = '${k3sDnsLabelPrefixOutbound}-${resourceNameSuffix}'

// Config data needed for dymanically created cloud-init config file.
@description('Name of managed identity used when creating cloud-init.yaml dynmically')
var identityName = 'boot'
var customRoleName = 'cloudinit-sp-${resourceNameSuffix}'

@description('Generate resource ID of managed identity since .id property appears to be unsupported')
var miId = resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', identityName)

var rancherDockerInstallUrl = 'https://releases.rancher.com/install-docker/18.09.sh'
var argocdInstallUrl = 'https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64'
var helmTarBall = 'helm-v3.7.1-linux-amd64.tar.gz'
var argocdVersion = '3.26.12'
var argocdNamespace = 'argocd'
var argocdReleaseName = 'argocd-demo'

// This variable is only used for testing purpose to allow SSH through the load balancert.  
// TO BE REMOVED
var sourceIP = '81.229.112.35'

var nicIpConfig = (lbDeployment == 'yes') ? {
  name: 'lbIpConfig'
  properties: {
    subnet: {
      id: subnetRef
    }
    privateIPAllocationMethod: 'Dynamic'
    loadBalancerBackendAddressPools: lb.properties.backendAddressPools
  }
} : {
  name: 'vmIpConfig1'
  properties: {
    subnet: {
      id: subnetRef
    }
    privateIPAllocationMethod: 'Dynamic'
    publicIPAddress: {
      id: publicIPAddress.id
    }
  }
}


// Create virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

// Create subnet
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-03-01' =  {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
    serviceEndpoints: serviceEndpoints
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

// Create empty network security group
resource nsg 'Microsoft.Network/networkSecurityGroups@2021-03-01' = {
  name: nsgName
  location: location
  tags: tags
}

// Allow SSH connections from specific source IP
resource sshRule 'Microsoft.Network/networkSecurityGroups/securityRules@2021-03-01' = {
  name: 'SSH'
  parent: nsg
  properties : {
    protocol: 'Tcp' 
    sourcePortRange:  '*'
    destinationPortRange:  '22'
    sourceAddressPrefix:   sourceIP
    destinationAddressPrefix: '*'
    access:  'Allow'
    priority: 100
    direction: 'Inbound'
    sourcePortRanges: []
    destinationPortRanges: []
    sourceAddressPrefixes: []
    destinationAddressPrefixes: []
  }
}

// Allow kubectl connections from anywhere
resource k8sRule 'Microsoft.Network/networkSecurityGroups/securityRules@2021-03-01' = {
  name: 'K8S'
  parent: nsg
  properties: {
    protocol:  'Tcp'
    sourcePortRange:  '*'
    destinationPortRange: null
    sourceAddressPrefix:  '*'
    destinationAddressPrefix:  '*'
    access:  'Allow'
    priority: 110
    direction:  'Inbound'
    sourcePortRanges: []
    destinationPortRanges: [
      '80'
      '443'
      '6443'
    ]
    sourceAddressPrefixes: []
    destinationAddressPrefixes: []
  }
}

// Create Public IP
resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2021-03-01' = {
  name: publicIPAddressName
  location: location
  tags: tags
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
    dnsSettings: {
      domainNameLabel: domainNameLabel
    }
  }
  sku: {
    name: 'Standard'
  }
}

resource publicIPAddressOutbound 'Microsoft.Network/publicIPAddresses@2021-03-01' = if (lbDeployment == 'yes') {
  name: publicIPAddressOutboundName
  location: location
  tags: tags
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
    dnsSettings: {
      domainNameLabel: domainNameLabelOutbound
    }
  }
  sku: {
    name: 'Standard'
  }
}

resource lb 'Microsoft.Network/loadBalancers@2021-05-01' = if (lbDeployment == 'yes') {
  name: lbName
  location: location
  sku:{
    name: 'Standard'
  }
  tags: tags
  properties: {
    frontendIPConfigurations: [
      {
        name:  lbFeAddressName
        properties: {
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
      // {
      //   name: lbFeIPAddressOutboundName
      //   properties: {
      //     publicIPAddress: {
      //       id: publicIPAddressOutbound.id
      //     }
      //   }
      // }
    ]
    backendAddressPools: [
      {
        name: lbBePoolName
      }
      // {
      //   name: lbBePoolNameOutbound
      // }
    ]
    probes: [
      {
        name: 'ssh'
        properties: {
          protocol:  'Tcp'
          port: 22
        }
      }
      {
        name: 'http'
        properties: {
          protocol: 'Tcp'
          port: 80
        }
      }
      {
        name: 'https'
        properties: {
          protocol: 'Tcp'
          port: 443
        }
      }
      {
        name: 'k8s'
        properties: {
          protocol: 'Tcp'
          port: 6443
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'ssh'
        properties: {
          backendPort: 22
          frontendPort: 22
          protocol: 'Tcp'
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, lbFeAddressName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBePoolName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'ssh')
          }
          enableFloatingIP: false
          idleTimeoutInMinutes: 15
          enableTcpReset: true
          loadDistribution: 'Default'
          disableOutboundSnat: true
        }
      }
      {
        name: 'http'
        properties: {
          backendPort: 80
          frontendPort: 80
          protocol: 'Tcp'
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, lbFeAddressName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBePoolName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'http')
          }
          enableFloatingIP: false
          idleTimeoutInMinutes: 15
          enableTcpReset: true
          loadDistribution: 'Default'
          disableOutboundSnat: true
        }
      }
      {
        name: 'https'
        properties: {
          backendPort: 443
          frontendPort: 443
          protocol: 'Tcp'
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, lbFeAddressName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBePoolName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'https')
          }
          enableFloatingIP: false
          idleTimeoutInMinutes: 15
          enableTcpReset: true
          loadDistribution: 'Default'
          disableOutboundSnat: true
        }
      }
      {
        name: 'k8s'
        properties: {
          backendPort: 6443
          frontendPort: 6443
          protocol: 'Tcp'
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, lbFeAddressName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBePoolName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'k8s')
          }
          enableFloatingIP: false
          idleTimeoutInMinutes: 15
          enableTcpReset: true
          loadDistribution: 'Default'
          disableOutboundSnat: true
        }
      }
    ]
    outboundRules: [
      {
        name: 'all'
        properties: {
          allocatedOutboundPorts: 10000
          protocol: 'All'
          enableTcpReset: false
          idleTimeoutInMinutes: 15
          frontendIPConfigurations: [
            {
              //id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, lbFeIPAddressOutboundName)
              id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, lbFeAddressName)
            }
          ]
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBePoolName)
          }
        }
      }
    ]
  }
}

// // Create test NICs. TO BE REMOVED!!!
// var count = 3
// resource nics 'Microsoft.Network/networkInterfaces@2021-03-01' = [for i in range(0, count): {
//   name: 'nic${(i + 1)}'
//   location: location
//   tags: tags
//   properties: {
//     ipConfigurations: [
//       {
//         name: 'ipconfigLB'
//         properties: {
//           subnet: {
//             id: subnetRef
//           }
//           privateIPAllocationMethod: 'Dynamic'
//           loadBalancerBackendAddressPools: lb.properties.backendAddressPools
//         }
//       }
//     ]
//     networkSecurityGroup: {
//       id: nsg.id
//     }
//   }
// } ]

// // Create NIC with direct Internet access
// resource nic 'Microsoft.Network/networkInterfaces@2021-03-01' = {
//   name: networkInterfaceName
//   location: location
//   tags: tags
//   properties: {
//     ipConfigurations: [
//       {
//         name: 'ipconfig1'
//         properties: {
//           subnet: {
//             id: subnetRef
//           }
//           privateIPAllocationMethod: 'Dynamic'
//           publicIPAddress: {
//             id: publicIPAddress.id
//           }
//         }
//       }
//     ]
//     networkSecurityGroup: {
//       id: nsg.id
//     }
//   }
// }

// // Create NIC behind load balancer
// resource nic 'Microsoft.Network/networkInterfaces@2021-03-01' = {
//   name: networkInterfaceName
//   location: location
//   tags: tags
//   properties: {
//     ipConfigurations: [
//       {
//         name: 'lbIpconfig'
//         properties: {
//           subnet: {
//             id: subnetRef
//           }
//           privateIPAllocationMethod: 'Dynamic'
//           loadBalancerBackendAddressPools: lb.properties.backendAddressPools
//         }
//       }
//     ]
//     networkSecurityGroup: {
//       id: nsg.id
//     }
//   }
// }

resource nic 'Microsoft.Network/networkInterfaces@2021-03-01' =  [for i in range(0, vmCount): {
  name: '${networkInterfaceNamePrefix}${(i + 1)}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      nicIpConfig
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
} ]

// Create virtual machine
resource vm 'Microsoft.Compute/virtualMachines@2021-03-01' =  [for i in range(0, vmCount): {
  name: '${vmNamePrefix}${(i)}'
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
      }
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic[i].id
        }
      ]
    }
    osProfile: {
      computerName: '${vmNamePrefix}${(i)}'
      adminUsername: linuxAdminUsername
      //adminPassword: adminPasswordOrKey
      linuxConfiguration: linuxConfiguration
      customData: generateCloudInitDeploymentScript.properties.outputs.cloudInitFileAsBase64
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: false
      }
    }
  }
} ]

// Create storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSkuName
  }
  kind: 'FileStorage'
  properties: {
    accessTier: 'Hot'
    networkAcls: nfs ? {
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          action: 'Allow'
          id: subnet.id
        }
      ]
    } : null
    supportsHttpsTrafficOnly: nfs ? false : true
  }
}

// Create file service
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2021-04-01' = {
  parent: storageAccount
  name: 'default'
}

// Create file share
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-04-01' = {
  parent: fileService
  name: fileShareName
  properties: {
    accessTier: 'Premium'
    shareQuota: 128
    enabledProtocols: nfs ? 'NFS' : 'SMB'
    rootSquash: nfs ? 'NoRootSquash' : null
  }
}

// Create user managed identity (to be used by custom deployment script)
resource mi 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: identityName
  location: location
}

resource deploymentScriptCustomRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' = {
  name: guid(customRoleName, resourceGroup().id)
  properties: {
    roleName: customRoleName
    description: 'Configure least privilege for the deployment principal in deployment script'
    permissions: [
      {
        actions: [
          'Microsoft.Storage/storageAccounts/*'
          'Microsoft.ContainerInstance/containerGroups/*'
          'Microsoft.Resources/deployments/*'
          'Microsoft.Resources/deploymentScripts/*'
          'Microsoft.Storage/register/action'
          'Microsoft.ContainerInstance/register/action'
        ]
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }    
}

resource miCustomRoleAssign 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(customRoleName, identityName, resourceGroup().id)
  properties: {
      roleDefinitionId: deploymentScriptCustomRole.id
      principalId: mi.properties.principalId
      principalType: 'ServicePrincipal'
  }
}

resource generateCloudInitDeploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'createCloudInit'
  location: resourceGroup().location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${miId}': {}
    }
  }
  properties: {
    azCliVersion: '2.24.0'
    environmentVariables: [
      {
        name: 'RANCHER_DOCKER_INSTALL_URL'
        value: rancherDockerInstallUrl
      }
      {
        name: 'ARGOCD_INSTALL_URL'
        value: argocdInstallUrl
      }
      {
        name: 'LINUX_ADMIN_USERNAME'
        value: linuxAdminUsername
      }
      {
        name: 'HELM_TAR_BALL'
        value: helmTarBall
      }
      {
        name: 'ARGOCD_VERSION'
        value: argocdVersion
      }
      {
        name: 'ARGOCD_NAMESPACE'
        value: argocdNamespace
      }
      {
        name: 'ARGOCD_RELEASE_NAME'
        value: argocdReleaseName
      }
      {
        name: 'HOST_IP_ADDRESS_OR_FQDN'
        value: publicIPAddress.properties.dnsSettings.fqdn
      }
    ]
    storageAccountSettings: {
      storageAccountName: storageAccountName
      storageAccountKey: listKeys(resourceId('Microsoft.Storage/storageAccounts', storageAccountName), '2021-04-01').keys[0].value
    }
    primaryScriptUri: cloudInitScriptUri
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}

output cloudInitFileAsBase64 string = generateCloudInitDeploymentScript.properties.outputs.cloudInitFileAsBase64
output fqdn string = publicIPAddress.properties.dnsSettings.fqdn
output miId string = miId
