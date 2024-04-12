<#
.SYNOPSIS
    VMWare App Volume and MS Teams (MSIX)
.DESCRIPTION
    Converts VMWare Workstation VMDK to vCenter VMDK (monolithic)
.NOTES
    Requires PowerCLI module
#>

#Region Variables

#MSIX File Names
$msix = "MS_Teams_v2-$(Get-Date -f yy.MM.dd)"
$msix_vmdk = "$($msix).vmdk"
$msix_json = "$($msix).json"

#vCenter Server and DataStore Names
$vCenter = "vcenter001.domain.net"
$DataStore = "DS_001"

#Credential Path
$cred_path = ".\creds.xml"

#Directory Paths
$filePath = "\\Server001.Domain.net\MSIX" 
$logPath = "$filePath\Logs\Convert_VMDK_$(Get-Date -f yyyy-MMM-dd_hh.mm.ss).txt"

#EndRegion Variables

Start-Transcript $logPath

Write-Host "Import Credentials"
if(!(Test-Path $cred_path)){
    $creds=Get-Credential -Message "Enter Creds in the format Domain\UserName"
}else{$creds = Import-Clixml -Path $cred_path}

Write-Host "Connect to vCenter"
try{
    Connect-VIServer -Server $vCenter -Credential $creds
}catch {Write-Error "Failed to Connect to vCenter"}

Write-Host "Validate MSIX Files"
if(!(Test-Path "$filePath\$msix_vmdk")){Write-Error "Missing VMDK"}
if(!(Test-Path "$filePath\$msix_json")){Write-Error "Missing JSON"}

Write-Host "Get and Map DataStore"
try{
    $DS = Get-Datastore $DataStore
    New-PSDrive -Location $DS -Name ds -PSProvider VimDatastore -Root "\"
}catch{Write-Error "Missing DataStore"}

Write-Host "Copy VMDK to Temp Folder on DataStore"
try{
    Copy-DatastoreItem -Item "$filePath\$msix_vmdk" -Destination "ds:\AppVolumes\temp\" -Force
}catch{Write-Error "Failed to Copy VMDK to DataStore."}

#validate VMDK file
$VMDK = Get-HardDisk -Datastore $DataStore -DatastorePath "[$DataStore] AppVolumes/temp/$msix_vmdk"
if(!($VMDK)){Write-Error "Workstation VMDK Missing on DataStore"}

Write-Host "Copy and Convert VMDK to Flat format"
try{
    Copy-HardDisk -HardDisk $VMDK -DestinationPath "[$DataStore] AppVolumes/apps/$msix" 
}catch{Write-Error "Failed to Copy Hard Disk"}

#validate VMDK file
$Flat_VMDK = Get-HardDisk -Datastore $DataStore -DatastorePath "[$DataStore] AppVolumes/apps/$msix_vmdk"
if(!($Flat_VMDK)){Write-Error "Flat VMDK Missing on DataStore"}

Write-Host "Upload JSON to AppFolder"
try{
    Copy-DatastoreItem -Item "$filePath\$msix_json" -Destination "ds:\AppVolumes\apps\" -Force
}catch{Write-Error "Failed to Copy MetaData to DataStore"}

Write-Host "Delete VMDK file from Temp folder"
try{
    $OldVMDK = Get-Item "ds:\AppVolumes\temp\$msix_vmdk"
    Remove-Item $oldVMDK -Force
}catch{Write-Error "Failed to Delete Temp VMDK"}

Write-Host "Remove Mapped Drive"
Remove-PSDrive -Name ds

Stop-Transcript

#END