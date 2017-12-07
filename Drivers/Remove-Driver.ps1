param
(
    [parameter(ValueFromPipeline=$true)]
    [ValidateScript({($_ | %{Test-Path -Path $_ -PathType Container}) -or (($_ | %{Test-Path -Path $_ -PathType Leaf}) -and ($_ | %{(Get-Item $_).Extension -eq '.inf'}))})]
    [String[]] $Path = @((Get-Location).Path),
    [Bool] $Transcript = $true,
    [Bool] $Recurse = $true,
    [String] $TranscriptPath = "$($env:TEMP)\Remove-Driver.log"
)

if($Transcript) {
    Start-Transcript -Path $TranscriptPath -Append -Force
}

# Set Script file path variables
$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptName = $MyInvocation.MyCommand.Name
$ScriptExt = (Get-Item $ScriptPath).extension
$ScriptBaseName = $ScriptName -replace($ScriptExt ,"")
$ScriptFolder = Split-Path -parent $ScriptPath

# Import TSUtility module
Import-Module "$ScriptFolder\IniFile.psm1" -Force

#  Search each input path for all .inf files, and store their full path in $FullName
[String[]]$FullName = @()
foreach ($dir in $Path) {
    if (Test-Path $dir -PathType Leaf) {
        $FullName += $dir
    } else {
        if ($Recurse) {
            $FullName += @(Get-ChildItem -Path $dir -Include *.inf -Recurse | Select -ExpandProperty FullName)
        } else {
            $FullName += @(Get-ChildItem -Path $dir | Where {$_.Extension -eq '.inf'} | Select -ExpandProperty FullName)
        }
    }
}

#  Generate list of currently installed drivers, and their associated .inf files
$OEMDrivers = @(Get-WindowsDriver -Online | Where-Object {($_.Driver -like 'oem*')})
foreach ($OEMDriver in $OEMDrivers) {
    $OEMDriver | Add-Member -Name 'FileName' -MemberType NoteProperty -Value ([String]($OEMDriver.OriginalFileName | Split-Path -Leaf))
    $OEMDriver | Add-Member -Name 'Ver' -MemberType NoteProperty -Value ([Version]($OEMDriver.Version))
}

#$OriginalFileNames = @($WindowsDrivers | Where-Object {$OEMDrivers -contains $_.Driver} | Select-Object -ExpandProperty OriginalFileName | Sort-Object -Unique)

$FullName = $FullName | Select -Unique | Sort
$FullName | %{Write-Host $_}

[Int]$FinalExitCode = 0

Write-Host "Ready to import $($FullName.Count) .inf files"
[Int]$BadINF = 0
[Int]$BadCount = 0
[Int]$Count = 0


foreach ($inf in $FullName) {

    Write-Host "Analyzing $($inf)"

    $DriverVer = @()

    #  Attempt to find driver version information within provided .inf files
    #  If the driver version information is missing, then skip file as invalid
    try {
        $DriverVer = @((Get-IniValue -File $inf -Section 'Version' -Key 'DriverVer').Split(','))
    } catch {
        Write-Error "Error reading $($inf)"
        $BadINF++
        continue
    }

    if ($DriverVer.Count -lt 2 -or [String]::IsNullOrEmpty($DriverVer[1])) {
        Write-Error "Unable to retrieve version information for $($inf)"
        $BadINF++
        continue
    }

    #  Attempt to convert the version from the .inf file into a version type,
    #  and throw error if unable to convert
    [Version]$Ver = '0.0.0'
    try {
        $Ver = ($DriverVer[1]).Split(';')[0]
    } catch {
        Write-Error "Invalid version number in $($inf)"
    }

    Write-Host "$($inf) is '$($DriverVer[0])', '$($Ver)'"
    
    #  Get the .inf filename without the path
    [String]$FileName = ''
    try {
        $FileName = (Get-Item -Path $inf).Name
    } catch {
        Write-Error "Unable to file name information for $($inf)"
        continue
    }

    #  Find installed drivers that match the .inf name and version number
    $RemoveDrivers = @()
    $RemoveDrivers = @($OEMDrivers | Where {$_.FileName -eq $FileName -and $_.Ver -eq $Ver})
    Write-Host "Found $($RemoveDrivers.Count) drivers to remove for $($inf)"

    #  For any installed drivers that match the .inf name and version number of the provided path,
    #  attempt to uninstall driver
    foreach ($RemoveDriver in $RemoveDrivers) {
        Write-Host "Removing $($RemoveDrivers.FileName), $($RemoveDrivers.Ver), $($RemoveDrivers.Driver)"
        Write-Host "$($RemoveDrivers.ClassName)"
        Write-Host "$($RemoveDrivers.ClassDescription)"
        Write-Host "$($RemoveDrivers.OriginalFileName)"
        $ProcessStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $ProcessStartInfo.FileName = 'pnputil.exe'
        $ProcessStartInfo.RedirectStandardError = $true
        $ProcessStartInfo.RedirectStandardOutput = $true
        $ProcessStartInfo.UseShellExecute = $false
        $ProcessStartInfo.Arguments = "-f -d `"$($RemoveDriver.Driver)`""
        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $ProcessStartInfo
        $Process.Start() | Out-Null
        $Process.WaitForExit() | Out-Null
        $StandardOutput = $Process.StandardOutput.ReadToEnd()
        $ExitCode = $Process.ExitCode

        if ($ExitCode -notin (0,3010)) {
            Write-Error "Import exited with $($ExitCode)"
            $StandardError = $Process.StandardError.ReadToEnd()
            Write-Host $StandardError
            $FinalExitCode = $ExitCode
            $BadCount++
        }
        $Count++
        Write-Host $StandardOutput
    }
}


Write-Host "Removed $($Count - $BadCount) of $($Count) drivers for $($FullName.Count) .inf files"
if ($BadINF -gt 0) {
    Write-Host "There were $($BadINF) invalid INF files"
}
Write-Host "Exiting $($FinalExitCode)"

Stop-Transcript

exit $FinalExitCode
