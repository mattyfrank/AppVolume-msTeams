<#
.SYNOPSIS
    Import AppVolume Packages via REST
.NOTES
    In Order To Import AppVolume Package Names Must Be Unique
    If AppVol Name Already Exists Import Will Fail
#>

param(
    [Parameter(Mandatory=$false)][String]$avServer="appvolume.domain.net",    
    [Parameter(Mandatory=$false)][String]$cred_path = ".\creds.xml",
    $AppVol_Datastore    = 'DS_001',
    $AppVol_Path         = 'AppVolumes/apps',
    $AppVol_Datadelay    = 'true'
)

#Get Creds
if(!(Test-Path $cred_path)){
    $creds=Get-Credential -Message "Enter Creds in the format Domain\UserName"
}else{$creds = Import-Clixml -Path $cred_path}

#Format Creds
$credentials = @{
    username = $creds.UserName
    password = $creds.GetNetworkCredential().Password
}

Write-Host "Connect to AppVolume Server '$($avServer)'"
$Session = Invoke-RestMethod -UseBasicParsing -SessionVariable avSession -Method Post -Uri "https://$avServer/app_volumes/sessions" -Body $credentials
if($Session.success -ne 'ok'){Write-Error "Failed to Connect to AppVol Server"}

#Format Vars
$AVDatacenter  = 'data[datacenter]'
$AVDatastore   = 'data[datastore]'
$Path          = 'data[path]' 
$Delay         = 'data[delay]'

#Format Body
$Body = @{
        $AVDatacenter = ''
        $AVDatastore  = $AppVol_Datastore
        $Path         = $AppVol_Path
        $Delay        = $AppVol_Datadelay
}
Write-Host $Body

Write-Host "Import App Volumes"
$Import = Invoke-WebRequest -WebSession $avSession -Method Post -Uri https://$avServer/app_volumes/app_products/import -Body $Body

Write-Host $Import.Content

Write-Host "Import Completed"