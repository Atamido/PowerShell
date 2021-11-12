param
(
    [parameter(ValueFromPipeline=$true)]
    [ValidateScript({($_ | ForEach-Object {Test-Path -Path $_ -PathType Container}) -or (($_ | ForEach-Object {Test-Path -Path $_ -PathType Leaf}) -and ($_ | ForEach-Object {(Get-Item $_).Extension -eq '.msu'}))})]
    [String[]] $Path = @((Get-Location).Path),
    [Bool] $Transcript = $true,
    [Bool] $Recurse = $true,
    [String] $TranscriptPath = "$($env:TEMP)\SMSTSLog\Install-Update.log"
)

if ($Transcript) {
    Start-Transcript -Path $TranscriptPath -Append -Force
}

$TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
$OSDisk = $TSEnv.Value('OSDisk')
Write-Host "OSDisk is '$($OSDisk)'"


[String[]]$FullName = @()

foreach ($dir in $Path) {
    if (Test-Path $dir -PathType Leaf) {
        $FullName += $dir
    }
    else {
        if ($Recurse) {
            $FullName += @(Get-ChildItem -Path $dir -Include *.msu -Recurse | Select -ExpandProperty FullName)
        }
        else {
            $FullName += @(Get-ChildItem -Path $dir | Where-Object {$_.Extension -eq '.msu'} | Select -ExpandProperty FullName)
        }
    }
}

$FullName = $FullName | Select -Unique | Sort
$FullName | %{Write-Host $_}

[Int]$FinalExitCode = 0

Write-Host "Ready to import $($FullName.Count) .msu files"
[Int]$BadCount = 0
[Int]$SkipCount = 0

foreach ($msu in $FullName) {

    Write-Host "Importing $($msu)"
    $Args = "/Image:$($OSDisk)\ /Add-Package /PackagePath:`"$($msu)`" /ScratchDir:`"$((Get-Location).Path)`""
    Write-Host "Command arguments are '$($Args)'"
    $ProcessStartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $ProcessStartInfo.FileName = 'dism.exe'
    $ProcessStartInfo.RedirectStandardError = $true
    $ProcessStartInfo.RedirectStandardOutput = $true
    $ProcessStartInfo.UseShellExecute = $false
    $ProcessStartInfo.Arguments = $Args
    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $ProcessStartInfo
    $Process.Start() | Out-Null
    $Process.WaitForExit() | Out-Null
    $StandardOutput = $Process.StandardOutput.ReadToEnd()
    $ExitCode = $Process.ExitCode

    #  2359302:     0x00240006 WU_S_ALREADY_INSTALLED The update to be installed is already installed on the system
    #  -2145124329: 0x80240017 WU_E_NOT_APPLICABLE Operation was not performed because there are no applicable updates.
    if (-not ((0,3010, 2359302, -2145124329) -contains $ExitCode)) {
        Write-Error "Import exited with $($ExitCode)"
        $StandardError = $Process.StandardError.ReadToEnd()
        Write-Host $StandardError
        $FinalExitCode = $ExitCode
        $BadCount++
    }
    elseif (-not ((0,3010) -contains $ExitCode)) {
        Write-Warning "Import exited with $($ExitCode)"
        $SkipCount++
    }
    else {
        Write-Host "Import exited with $($ExitCode)"
    }
    Write-Host $StandardOutput
}

Write-Host "Installed $($FullName.Count - $BadCount - $SkipCount) of $($FullName.Count) .msu files"
if ($SkipCount -gt 0) {
    Write-Host "Skipped $($SkipCount) of $($FullName.Count) .msu files"
}
Write-Host "Exiting $($FinalExitCode)"

if ($Transcript) {
    Stop-Transcript
}

exit $FinalExitCode
