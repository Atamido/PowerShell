#  Collect OEM drivers the OS is using for attached hardware, and copy them out so that they can be inserted into a driver package


#  Set up destination directory for drivers
$DriverRoot = 'C:\Temp\DriverCollection'
$DateTime = Get-Date -Format yyyyMMddhhmmss
$DriverFolder = "$($DriverRoot)\$($DateTime)"
If (!(Test-Path -Path $DriverFolder -PathType Container))
{
    New-Item -Path $DriverRoot -Name $DateTime -ItemType Directory -Force | Out-Null
}
If (!(Test-Path -Path "$($DriverRoot)\Copy-Driver.ps1" -PathType Leaf))
{
    Copy-Item -Path $PSCommandPath -Destination $DriverRoot -Force
}
Write-Host "Working directory: $($DriverFolder)"
"Working directory: $($DriverFolder)" | Out-File -FilePath "$($DriverFolder)\DriverCollectionLog.txt" -Append

#  A little information about the system
gwmi win32_computersystem | Format-List | Out-File -FilePath "$($DriverFolder)\DriverCollectionLog.txt" -Append

#  Get list of drivers being used for attached hardware
#  Exclude the Dell Command Monitor driver 'dcdbas'
#  Exclude the Cisco VPN driver 'VPNVA'
$PnPSignedDrivers = @(Get-WmiObject Win32_PnPSignedDriver | Where-Object {($_.HardWareID -notlike '*dcdbas') -and ($_.HardWareID -ne 'VPNVA')})
$OEMPnPSignedDrivers = @($PnPSignedDrivers | Where-Object {$_.InfName -like 'oem*'})
[string[]]$OEMDrivers = $OEMPnPSignedDrivers | Select-Object -ExpandProperty InfName | Sort-Object -Unique
Write-Host "$($OEMDrivers.Count) OEM drivers in use by $($OEMPnPSignedDrivers.Count) devices"
"$($OEMDrivers.Count) OEM drivers in use by $($OEMPnPSignedDrivers.Count) devices" | Out-File -FilePath "$($DriverFolder)\DriverCollectionLog.txt" -Append

#  Get list of drivers installed on the system, which includes where the driver files are located
$WindowsDrivers = @(Get-WindowsDriver -Online | Where-Object {($_.Driver -like 'oem*') -and ($_.InfName -notlike 'dcdbas*') -and ($_.InfName -notlike 'vpnva*')})
$OriginalFileNames = @($WindowsDrivers | Where-Object {$OEMDrivers -contains $_.Driver} | Select-Object -ExpandProperty OriginalFileName | Sort-Object -Unique)
Write-Host "$($WindowsDrivers.Count) OEM drivers installed"
"$($WindowsDrivers.Count) OEM drivers installed" | Out-File -FilePath "$($DriverFolder)\DriverCollectionLog.txt" -Append

#  Create list of drivers that have already been copied to the driver folder so only new drivers are copied during this run of the script
[String[]]$Copied = Get-ChildItem -Path "$($DriverRoot)\*\*" -Directory | Select-Object -ExpandProperty Name | Sort-Object -Unique
Write-Host "$($Copied.Count) drivers already copied"
"$($Copied.Count) drivers already copied" | Out-File -FilePath "$($DriverFolder)\DriverCollectionLog.txt" -Append

#  Associage the drivers being used by hardware with the driver file locations, and copy those files out
$Count = 0
ForEach ($OriginalFileName in $OriginalFileNames) {
    $OEMFolder = (Get-Item -Path $OriginalFileName).Directory
    If ($Copied -notcontains $OEMFolder.Name)
    {
        Copy-Item -Path $OEMFolder.FullName -Destination $DriverFolder -Recurse
        $Count++
    }
}
Write-Host "$($Count) new drivers copied"
"$($Count) new drivers copied" | Out-File -FilePath "$($DriverFolder)\DriverCollectionLog.txt" -Append

#  Output a pretty table of OEM drivers
$OEMHash = @{}
$WindowsDrivers | ForEach {$OEMHash[$_.Driver] = $_}
$OEMPnPSignedDrivers | Sort-Object -Property devicename | ForEach {Add-Member -InputObject $_ -MemberType NoteProperty -Name 'OriginalFileName' -Value ($OEMHash[$_.InfName].OriginalFileName -replace '(.*\\)(.*?)(\\.*)','$2')}
$OEMPnPSignedDrivers | Sort-Object -Property devicename | ForEach {Add-Member -InputObject $_ -MemberType NoteProperty -Name 'Date' -Value ($_.DriverDate.Substring(0,8))}
$OEMPnPSignedDrivers | Sort-Object -Property devicename | Format-Table  -Property OriginalFileName,DeviceName,DriverVersion,Date,DriverProviderName,InfName,HardwareID -AutoSize | Out-File -FilePath "$($DriverFolder)\DriverCollectionLog.txt" -Append
$OEMPnPSignedDrivers | Sort-Object -Property devicename | Select-Object -Property OriginalFileName,DeviceName,DriverVersion,Date,DriverProviderName,InfName,HardwareID | Export-Csv -Path "$($DriverFolder)\DriverCollectionLog.csv" -NoTypeInformation

#  We don't want these files in the Driver Packages as they're extras, so delete them now
Get-ChildItem -Path $DriverRoot -Recurse | Where-Object {$_.Extension -eq '.pnf'} | Remove-Item -Force
