// ------------------------------------------------------------
//  Copyright (c) Microsoft Corporation.  All rights reserved.
//  Licensed under the MIT License (MIT). See License.txt in the repo root for license information.
// ------------------------------------------------------------
targetScope = 'subscription'

@description('The common name for this application')
param applicationName string

@description('Resource prefix for Azure resource group and its resources')
param resourcePrefix string = applicationName

@description('Load balancer (yes/no)')
param lbDeployment string

@description('Virtual machine has public IP address (yes/no)')
param vmPublicIp string

var applicationNameWithoutDashes = '${replace(applicationName,'-','')}'
var k3sName = '${take('k3s-${applicationNameWithoutDashes}',20)}'
//var resourceGroupName = 'rg-${resourcePrefix}'
var resourceGroupName = 'rg-${applicationNameWithoutDashes}'

@description('Location of resources')
@allowed([
  'eastasia'
  'southeastasia'
  'centralus'
  'eastus'
  'eastus2'
  'westus'
  'northcentralus'
  'southcentralus'
  'northeurope'
  'westeurope'
  'japanwest'
  'japaneast'
  'brazilsouth'
  'australiaeast'
  'australiasoutheast'
  'southindia'
  'centralindia'
  'westindia'
  'jioindiawest'
  'jioindiacentral'
  'canadacentral'
  'canadaeast'
  'uksouth'
  'ukwest'
  'westcentralus'
  'westus2'
  'koreacentral'
  'koreasouth'
  'francecentral'
  'francesouth'
  'australiacentral'
  'australiacentral2'
  'uaecentral'
  'uaenorth'
  'southafricanorth'
  'southafricawest'
  'switzerlandnorth'
  'switzerlandwest'
  'germanynorth'
  'germanywestcentral'
  'norwaywest'
  'norwayeast'
  'brazilsoutheast'
  'westus3'
  'swedencentral'
])
param location string = 'westeurope'

// Params below added for K3s cluster creation
@description('The type of environment.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environmentType string = 'dev'
param linuxAdminUsername string = 'adminuser'
//@secure()
param sshRSAPublicKey string = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC8RNrV7L0MvmkqTi8BELkTx6zb0BwNOo+sqorHRd/XdJj/bnEcVBKTcfVFxYYwljtqhKTUUGzAubRNpcFQkQ+uv8fRdEvjDJnIetk1nDXt7bGp5ZWW4t1dUbdmFSMYa4xUC4d6cwKn6c7Ft4D2zZLkJ2w9iz9LHyno8d+X3xYwUdsuJEUy+3SDvdUoigen5tsxSVXkveNYlitETgASyswxEq22FhEwhdeOu7RtCyL8sLClXyax2RJM/fkd9k2UPhqClXSR0CQZ+LVwo9ak5jTkW0iwokXq2YBaXsiGTIFP4OLVEU+tvGAvewgJxTN6+yykCkjqKR0I57lc6zTCWUdCjcoRkUwel/16MR4vo7b2BqGv2/QJMWx9TqXDH4EqhvcKXwaWMTfmgCbdEGDlZ0di4maLztHm19opVY+UpQxh/mutOnrPYVeQfaKiNOImLXdISDvU3n6hBH/JDHl3iTID+KPZEm/ao4JUoc3sLfaD/QDrqDBKCp1thLJjhMkDP52f+IexNVqfBTlrDTW1Exuq0w0jrVA7firvBaW6/fB6lz70F46CT0y47k2ttV1ChknALlf9s+4czRSRY1qzCidIuF5epIumbKHR2kMrTF5XUV6X3/z1yRRCHJKMq4ibMfN/1zErCeh47EFynrA9E5/7wNUV4GfhcpIMgi14IPh0PQ== pelleo@pelleopc'
param cloudInitScriptUri string

@description('DNS label of external IP address')
param dnsLabelPrefix string = resourcePrefix

@description('DNS label of external IP address (outbound load balancer NAT)')
param dnsLabelPrefixOutbound string = '${resourcePrefix}-outbound'

// VM info
param vmCount int
@description('Size of virtual machine.')
param vmSize string = 'standard_d4s_v3'

// Load balancer info
param lbName string  = '${resourcePrefix}-lb'

// Storage info
@minLength(3)
@maxLength(63)
@description('Name of file share.  Must be between 3 and 63 characters long.')
param fileShareName string = resourcePrefix

@allowed([
  'SMB'
  'NFS'
])
@description('Fileshare type.  Must be SMB or NFS.')
param fileShareType string = 'SMB'

@description('Storage account prefix')
param storageAccountNamePrefix string = '${resourcePrefix}store'

param tags object = {
  owner: 'user@contoso.com'
  project: 'Hybrid.IoTHub'
  version:  '1.0'
  timestamp: utcNow()
  env: environmentType
}

resource rg 'Microsoft.Resources/resourceGroups@2020-10-01' = {
  name: resourceGroupName 
  location: location
}

module cluster 'modules/cluster.bicep' = {
  name: '${resourcePrefix}Deployment'
  scope: resourceGroup(rg.name)
  params: {
    location: location
    resourcePrefix: resourcePrefix
    vmCount: vmCount
    vmSize: vmSize
    lbName: lbName
    storageAccountNamePrefix: storageAccountNamePrefix
    fileShareName: fileShareName
    fileShareType: fileShareType
    environmentType: environmentType
    linuxAdminUsername: linuxAdminUsername
    sshRSAPublicKey: sshRSAPublicKey
    dnsLabelPrefix: dnsLabelPrefix
    dnsLabelPrefixOutbound : dnsLabelPrefixOutbound 
    cloudInitScriptUri: cloudInitScriptUri
    lbDeployment: lbDeployment
    vmPublicIp: vmPublicIp
    tags: tags
  }
}

// TODO: modify
output k3sName string = k3sName
//output clusterPrincipalID string = aks.outputs.clusterPrincipalID
output clusterFqdn string = cluster.outputs.fqdn
output resourceGroupName string = rg.name
