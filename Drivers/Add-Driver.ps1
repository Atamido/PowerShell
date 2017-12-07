param
(
    [parameter(ValueFromPipeline=$true)]
    [ValidateScript({($_ | %{Test-Path -Path $_ -PathType Container}) -or (($_ | %{Test-Path -Path $_ -PathType Leaf}) -and ($_ | %{(Get-Item $_).Extension -eq '.inf'}))})]
    [String[]] $Path = @((Get-Location).Path),
    [Bool] $Transcript = $true,
    [Bool] $Install = $true,
    [Bool] $Recurse = $true,
    [String] $TranscriptPath = "$($env:TEMP)\Add-Driver.log"
)

if($Transcript) {
    Start-Transcript -Path $TranscriptPath -Append -Force
}

$InstallSwitch = ''
if($Install) {
    $InstallSwitch = '-i'
}

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

$FullName = $FullName | Select -Unique | Sort
$FullName | %{Write-Host $_}

[Int]$FinalExitCode = 0

Write-Host "Ready to import $($FullName.Count) .inf files"
[Int]$BadCount = 0
[Int]$AddCount = 0


#  Attempt to install each driver
foreach ($inf in $FullName) {
    Write-Host "Importing $($inf)"
    $ProcessStartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $ProcessStartInfo.FileName = 'pnputil.exe'
    $ProcessStartInfo.RedirectStandardError = $true
    $ProcessStartInfo.RedirectStandardOutput = $true
    $ProcessStartInfo.UseShellExecute = $false
    $ProcessStartInfo.Arguments = "$($InstallSwitch) -a `"$($inf)`""
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
        
        # If the driver can't be applied to specific hardware, then it may fail with exit code 259
        # If it does, then we'll try to add the driver to the driver store without applying it to hardware
        if ($ExitCode -eq 259) {
            Write-Host "Importing $($inf)"
            $ProcessStartInfo = New-Object System.Diagnostics.ProcessStartInfo
            $ProcessStartInfo.FileName = 'pnputil.exe'
            $ProcessStartInfo.RedirectStandardError = $true
            $ProcessStartInfo.RedirectStandardOutput = $true
            $ProcessStartInfo.UseShellExecute = $false
            $ProcessStartInfo.Arguments = "-a `"$($inf)`""
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
            } else {
                $AddCount++
            }
        } else {
            $FinalExitCode = $ExitCode
            $BadCount++
        }


    }
    Write-Host $StandardOutput
}

Write-Host "Installed $($FullName.Count - $BadCount - $AddCount) of $($FullName.Count) .inf files"
if ($AddCount -gt 0) {
    Write-Host "Imported $($AddCount) of $($FullName.Count) .inf files"
}
Write-Host "Exiting $($FinalExitCode)"

Stop-Transcript
exit $FinalExitCode
