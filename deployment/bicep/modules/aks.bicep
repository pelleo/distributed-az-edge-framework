// ------------------------------------------------------------
//  Copyright (c) Microsoft Corporation.  All rights reserved.
//  Licensed under the MIT License (MIT). See License.txt in the repo root for license information.
// ------------------------------------------------------------
@maxLength(20)
@description('AKS Name')
param aksName string

// Required for Azure CNI (a. k. a. advanced networking)
param vnetName string = 'aks-vnet'
param subnetName string = 'aks-snet'

@description('Address space of virtual network')
var vnetAddressPrefix = '10.2.0.0/16'

@description('Address space of subnet prefix')
var subnetAddressPrefix  = '10.2.0.0/23'

// optional params
@minValue(0)
@maxValue(1023)
param osDiskSizeGB int = 0

@minValue(1)
@maxValue(50)
param agentCount int = 3

param agentVMSize string =  'standard_d4s_v3'


resource aks 'Microsoft.ContainerService/managedClusters@2020-09-01' = {
  name: aksName
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enableRBAC: true
    dnsPrefix: uniqueString(aksName)
    agentPoolProfiles: [
      {
        name: 'agentpool'
        enableAutoScaling: false
        osDiskSizeGB: osDiskSizeGB
        count: agentCount
        vmSize: agentVMSize
        osType: 'Linux'
        mode: 'System'
        vnetSubnetID: subnet.id
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      dockerBridgeCidr: '172.17.0.1/16'
      serviceCidr: '10.3.0.0/23'
      dnsServiceIP: '10.3.0.10'
    }
    servicePrincipalProfile: {
      clientId: 'msi'
    }
  }
}

// Create virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: vnetName
  location: resourceGroup().location
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
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

output controlPlaneFQDN string = aks.properties.fqdn
output aksName string = aks.name
output clusterPrincipalID string = aks.properties.identityProfile.kubeletidentity.objectId


