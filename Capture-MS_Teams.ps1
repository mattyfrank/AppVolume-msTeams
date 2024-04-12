<#
.SYNOPSIS
    VMWare App Volume and MS Teams (MSIX)

.DESCRIPTION
    Scripted way to package MS Teams into App Volume product in vCenter environment. 

.COMPONENT
    Pre-requisites:
    * HyperV Must Be Installed To Create VHD File w PowerShell. Requires a Restart
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

    * AppVolume CMD Line Tools (Located on the AppVolume ISO)
        $AVTools = "A:\Installation\Tools\App Volumes Tools.msi"
        msiexec.exe /i `"$AVTools`" /qb /l*v .\Install-AppVolTools.log


.NOTES
    * Nested Virtulalization Must be Enabled to Install HyperV on a VM (Expose hardware assisted virtualization to the guest OS).
    * AppVolume CMD Line Tools must be run as admin. 
    * AppVolume CMD Line Tool will convert VHD into VMDK for VMWare Workstation. 
    * Workstation VMDK is not compatiable with vCenter and needs to be converted to Monolithic Disk. 
    * Bypass Uploading Template (*_workstation.vmdk) and use PowerCLI Copy-HardDisk. This will convert disk to monolithic.
    * VMDK File Name Must Be Unique or Import Will Fail.

.LINK
    MS Teams MSIX & AppVol Documentation: https://kb.vmware.com/s/article/97141
    AppVol CMD Tool: https://docs.vmware.com/en/VMware-App-Volumes/2312/app-volumes-admin-guide/GUID-AD1F52B2-A450-4F4A-A939-4CC3ABBB6621.html
    Shout-Out: https://roderikdeblock.com/automate-the-complete-capturing-process-using-app-volumes-tools/

.EXAMPLE
    & .\New_msTeams_AppVol.ps1

#>

#Region Variables

#temp dir
$WorkingDir = "C:\Temp"

#Log path
$LogPath = "$WorkingDir\AppVol_msTeams_$(Get-Date -f yyyyMMMdd_hh.mm.ss).txt"

#VHD dir
$dVHD = 'C:\VHD'

#VHD Name
$ver = (get-date -format yy.MM.dd)
$msVHD = "MS_Teams_2-" + $ver

#VHD path
$VHDpath = $dVHD + '\' + $msVHD + '.vhd'

#VMDK paths
$VMDKpath = $VHDpath.Replace('vhd','vmdk')
$JSONpath = $VHDpath.Replace('vhd','json')

#UNC path
$Server = "\\Server001.Domain.net\MSIX" 

#Download paths
$msixmgrURI = 'https://aka.ms/msixmgr'
$msTeamsURI = 'https://go.microsoft.com/fwlink/?linkid=2196106'

#EndRegion Variables

#Stop on Error
$ErrorActionPreference = "Stop"

Start-Transcript $LogPath

if(!(Test-Path $WorkingDir)){New-Item -ItemType Directory $WorkingDir}
Write-Host "Change Directory to '$($WorkingDir)'"
cd $WorkingDir

try{
    Write-Host "Download MSIXMGR"
    $webObj = New-Object System.Net.WebClient
    $webObj.DownloadFile($msixmgrURI,"$WorkingDir\msixmgr.zip")
    Write-Host "Downloaded MSIXMGR"
}catch{Write-Error "Failed to Download MSIX Manager"}
Start-Sleep -seconds 2

try{
    Write-Host "Download MS Teams (msix)"
    $webObj.DownloadFile($msTeamsURI,"$WorkingDir\MSTeams-x64.msix")
    Write-Host "Downloaded MS Teams"
}catch{Write-Error "Failed to Download MS Teams"}
Start-Sleep -seconds 2

try{
    Write-Host "Extract MSIXMGR to '$($WorkingDir)'"
    Expand-Archive "$WorkingDir\msixmgr.zip" "$WorkingDir\msixmgr" -Force
}catch {Write-Error "Failed to Extract MSIX Manager"}


if(!(Get-WindowsOptionalFeature -Online -FeatureName *Hyper-V*)){Write-Error "HyperV Feature Missing"}
try{
    Write-Host "Create VHD '$($VHDpath)'"
    New-VHD -sizeBytes 1024MB -path "$VHDpath" -Confirm:$false -Dynamic
    Write-Host "Mount VHD '$($VHDpath)'"
    $VHDobject = Mount-VHD "$VHDpath" -PassThru -Verbose
    Write-Host "Mounted '$($VHDobject)'"
    Write-Host "Initialize Disk"
    $Disk = Initialize-disk -number $VHDobject.number -PassThru -Verbose
    Write-Host "Initialized Disk '$(($Disk).FriendlyName)'"
    Write-Host "Set Partition & Assig Drive Letter"
    $Partition = New-Partition -disknumber $Disk.number -assignDriveLetter -useMaximumSize -Verbose
    Write-Host "Format VHD"
    Format-Volume -filesystem NTFS -confirm:$false -DriveLetter $Partition.Driveletter -Force -Verbose
    $PartitionPath = $Partition.DriveLetter + ':\'
}catch{Write-Error "New VHD Failed"}

try{
    Write-Host "Copy MSIX files to VHD"
    $msixmgrDest = $PartitionPath + 'WindowsApps'
    Write-Host "Unpack MSIX to '$($msixmgrDest)'"
    & "$WorkingDir\msixmgr\x64\msixmgr.exe" -Unpack -packagePath "$WorkingDir\$MSTeams" -destination "$msixmgrDest" -applyACLs
    $packageName = get-childitem -Path "$msixmgrDest" -name
    Write-Host "Unpacked '$($packageName)' at '$($msixmgrDest)'"
}catch{Write-Error "Failed to UnPack MSIX"}

try{
    Write-Host "Dismount '$($VHDpath)'"
    Dismount-VHD "$VHDpath" -Verbose
}catch{Write-Error "Failed to DisMount VHD"}

try{
    Write-Host "Create META and JSON Files"
    $AppCapture = "C:\Program Files (x86)\VMware\AppCapture\appcapture.exe"
    if(!(Test-Path $AppCapture)){Write-Error "AppCapture.exe Missing"}
    & "C:\Program Files (x86)\VMware\AppCapture\appcapture.exe" /addmeta "$VHDpath" /msix "WindowsApps\$packageName" 
}catch{Write-Error "Failed to Create Meta File"}

$AVtools = "C:\Program Files (x86)\VMware\AppCapture\appcapture.exe"
if(!(Test-Path $AVtools)){Write-Error "Missing AppVol CMD Tools"}
try{
    Write-Host "Converting VHD to VMDK"
    & $AVtools /msixvmdk "$VHDpath" 
}catch {Write-Error "Failed to Convert VHD to VMDK"}

#Copy VMDK and JSON files to Server with Access to vCenter
if(!(Test-Path $Server)){Write-Error "Server Path Missing"}
try{
    Write-Host "Copy Files to '$($Server)'"
    New-PSDrive -PSProvider FileSystem -Root "$($Server)" -Name S -Credential $(Get-Credential)
    Copy-Item $VMDKpath S:\
    Copy-Item $JSONpath S:\
    Remove-PSDrive -Name S
}catch{Write-Error "Failed to Copy Files to Server"}

Write-Host "Convert VMDK File to vCenter Format & Import into AppVolume"

Stop-Transcript

#END