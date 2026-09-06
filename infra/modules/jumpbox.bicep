metadata description = 'Azure Bastion and a Linux jumpbox, so the private landing zone can be reached without exposing anything to the internet.'

@description('Base name used to derive resource names.')
@minLength(3)
@maxLength(20)
param baseName string

@description('Location for the jumpbox resources.')
param location string

@description('Tags applied to all resources.')
param tags object = {}

@description('Resource ID of the subnet the jumpbox VM joins.')
param jumpboxSubnetResourceId string

@description('Resource ID of the AzureBastionSubnet.')
param bastionSubnetResourceId string

@description('Administrator username for the jumpbox.')
param adminUsername string = 'azureuser'

@description('Administrator password for the jumpbox. Supply at deployment time; never commit it.')
@secure()
param adminPassword string

@description('Size of the jumpbox virtual machine.')
param vmSize string = 'Standard_D2s_v5'

var abbrs = loadJsonContent('../abbreviations.json')

module bastion 'br/public:avm/res/network/bastion-host:0.8.2' = {
  name: 'bas-${baseName}'
  params: {
    name: 'bas-${baseName}'
    location: location
    tags: tags
    virtualNetworkResourceId: split(bastionSubnetResourceId, '/subnets/')[0]
    publicIPAddressObject: {
      name: '${abbrs.publicIpAddress}bas-${baseName}'
      skuName: 'Standard'
      publicIPAllocationMethod: 'Static'
    }
    skuName: 'Standard'
  }
}

module jumpbox 'br/public:avm/res/compute/virtual-machine:0.22.3' = {
  name: 'vm-${baseName}'
  params: {
    name: take('vm-${baseName}', 15)
    computerName: take('vm${replace(baseName, '-', '')}', 15)
    location: location
    tags: tags
    vmSize: vmSize
    osType: 'Linux'
    adminUsername: adminUsername
    adminPassword: adminPassword
    disablePasswordAuthentication: false
    encryptionAtHost: false
    availabilityZone: 1
    imageReference: {
      publisher: 'Canonical'
      offer: 'ubuntu-24_04-lts'
      sku: 'server'
      version: 'latest'
    }
    osDisk: {
      caching: 'ReadWrite'
      diskSizeGB: 64
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    nicConfigurations: [
      {
        name: 'nic-${baseName}'
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: jumpboxSubnetResourceId
          }
        ]
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
  }
}

@description('Name of the jumpbox virtual machine.')
output jumpboxName string = jumpbox.outputs.name

@description('Name of the Bastion host used to reach the jumpbox.')
output bastionName string = bastion.outputs.name

@description('Principal ID of the jumpbox system-assigned identity.')
output jumpboxPrincipalId string = jumpbox.outputs.?systemAssignedMIPrincipalId ?? ''
