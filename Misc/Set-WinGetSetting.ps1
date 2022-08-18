function Set-WinGetSetting {
    [CmdletBinding()]
    Param (
        [Parameter(
            HelpMessage = 'Number of minutes before source update'
        )]
        [ValidateRange(0, 43200)]
        [Int]
        $AutoUpdateIntervalInMinutes,

        [Parameter(
            HelpMessage = 'Progress bar display style'
        )]
        [ValidateSet('accent', 'rainbow', 'retro')]
        [String]
        $ProgressBar,

        [Parameter(
            HelpMessage = 'Preferred logging level'
        )]
        [ValidateSet('verbose', 'info', 'warning', 'error', 'critical')]
        [String]
        $LoggingLevel,

        [Parameter(
            HelpMessage = 'The scope of a package install'
        )]
        [ValidateSet('user', 'machine')]
        [String]
        $PreferredScope,

        [Parameter(
            HelpMessage = 'The locales of a package install'
        )]
        [ValidatePattern('^([a-zA-Z]{2}|[iI]-[a-zA-Z]+|[xX]-[a-zA-Z]{1,8})(-[a-zA-Z]{1,8})*$')]
        [ValidateCount(1, 10)]
        [ValidateLength(1, 20)]
        [String[]]
        $PreferredLocale,

        [Parameter(
            HelpMessage = 'The architecture(s) to use for a package install'
        )]
        [ValidateSet('neutral', 'x64', 'x86', 'arm64', 'arm')]
        [ValidateCount(1, 4)]
        [String[]]
        $PreferredArchitectures,

        [Parameter(
            HelpMessage = 'The scope of a package install'
        )]
        [ValidateSet('user', 'machine')]
        [String]
        $RequiredScope,

        [Parameter(
            HelpMessage = 'The locales of a package install'
        )]
        [ValidatePattern('^([a-zA-Z]{2}|[iI]-[a-zA-Z]+|[xX]-[a-zA-Z]{1,8})(-[a-zA-Z]{1,8})*$')]
        [ValidateCount(1, 10)]
        [ValidateLength(1, 20)]
        [String[]]
        $RequiredLocale,

        [Parameter(
            HelpMessage = 'The architecture(s) to use for a package install'
        )]
        [ValidateSet('neutral', 'x64', 'x86', 'arm64', 'arm')]
        [ValidateCount(1, 4)]
        [String[]]
        $RequiredArchitectures,

        [Parameter(
            HelpMessage = 'Controls whether blocking warning messages shown to the user during an install or upgrade are ignored'
        )]
        [Bool]
        $IgnoreWarnings,

        [Parameter(
            HelpMessage = 'Controls whether installation notes are shown after a successful install'
        )]
        [Bool]
        $DisableInstallNotes,

        [Parameter(
            HelpMessage = 'The default root directory where packages are installed to under User scope. Applies to the portable installer type.'
        )]
        [String]
        $PortablePackageUserRoot,

        [Parameter(
            HelpMessage = 'The default root directory where packages are installed to under Machine scope. Applies to the portable installer type.'
        )]
        [String]
        $PortablePackageMachineRoot,

        [Parameter(
            HelpMessage = 'Default install location to use for packages that require it when not specified'
        )]
        [String]
        [ValidateLength(1, 32767)]
        $DefaultInstallRoot,

        [Parameter(
            HelpMessage = 'Controls whether the default behavior for uninstall removes all files and directories relevant to this package. Only applies to the portable installerType.'
        )]
        [Bool]
        $PurgePortablePackage,

        [Parameter(
            HelpMessage = 'Controls whether telemetry events are written'
        )]
        [Bool]
        $DisableTelemetry,

        [Parameter(
            HelpMessage = 'Control which download code is used for packages'
        )]
        [ValidateSet('default', 'wininet', 'do')]
        [String]
        $Downloader,

        [Parameter(
            HelpMessage = 'Number of seconds to wait without progress before fallback'
        )]
        [ValidateRange(1, 600)]
        [Int]
        $DoProgressTimeoutInSeconds,

        [Parameter(
            HelpMessage = 'Controls whether interactive prompts are shown by the Windows Package Manager client'
        )]
        [Bool]
        $DisableInteractive,

        [Parameter(
            HelpMessage = 'Reference implementation for an experimental command'
        )]
        [Bool]
        $ExperimentalCMD,

        [Parameter(
            HelpMessage = 'Reference implementation for an experimental argument'
        )]
        [Bool]
        $ExperimentalARG,

        [Parameter(
            HelpMessage = 'Support for package dependencies'
        )]
        [Bool]
        $Dependencies,

        [Parameter(
            HelpMessage = 'Enable use of MSI APIs rather than msiexec for MSI installs'
        )]
        [Bool]
        $DirectMSI,

        [Parameter(
            HelpMessage = 'Enable support for installing zip packages.'
        )]
        [Bool]
        $zipInstall,

        [Parameter(
            HelpMessage = 'Used to override the logging setting and create a verbose log.'
        )]
        [Bool]
        $LocalManifestFiles,

        [Parameter(
            HelpMessage = 'Passthru a psobject of the settings.json'
        )]
        [Switch]
        $Passthru
    )
    Begin {
        [String[]]$WinGetArgs = $null
        [String[]]$JSPath = $null
        [String[]]$NoteMembers = $null
        [String]$ParamArgString = $null
        [String]$Name = $null
        [Int]$PathCount = 0
        [Bool]$UpdateJSON = $false
        [String[]]$IgnoreParams = @('Passthru')

        $Mapping = @{}
        $Mapping['AutoUpdateIntervalInMinutes'] = @('autoUpdateIntervalInMinutes', 'source')
        $Mapping['ProgressBar'] = @('progressBar', 'visual')
        $Mapping['LoggingLevel'] = @('level', 'logging')
        $Mapping['PreferredScope'] = @('scope', 'installBehavior/preferences')
        $Mapping['PreferredLocale'] = @('locale', 'installBehavior/preferences')
        $Mapping['PreferredArchitectures'] = @('architectures', 'installBehavior/preferences')
        $Mapping['RequiredScope'] = @('scope', 'installBehavior/requirements')
        $Mapping['RequiredLocale'] = @('locale', 'installBehavior/requirements')
        $Mapping['RequiredArchitectures'] = @('architectures', 'installBehavior/requirements')
        $Mapping['IgnoreWarnings'] = @('ignoreWarnings', 'installBehavior')
        $Mapping['DisableInstallNotes'] = @('disableInstallNotes', 'installBehavior')
        $Mapping['PortablePackageUserRoot'] = @('portablePackageUserRoot', 'installBehavior')
        $Mapping['PortablePackageMachineRoot'] = @('portablePackageMachineRoot', 'installBehavior')
        $Mapping['DefaultInstallRoot'] = @('defaultInstallRoot', 'installBehavior')
        $Mapping['PurgePortablePackage'] = @('purgePortablePackage', 'uninstallBehavior')
        $Mapping['DisableTelemetry'] = @('disable', 'telemetry')
        $Mapping['Downloader'] = @('downloader', 'network')
        $Mapping['DoProgressTimeoutInSeconds'] = @('doProgressTimeoutInSeconds', 'network')
        $Mapping['DisableInteractive'] = @('disable', 'interactivity')
        $Mapping['ExperimentalCMD'] = @('experimentalCMD', 'experimentalFeatures')
        $Mapping['ExperimentalARG'] = @('experimentalARG', 'experimentalFeatures')
        $Mapping['Dependencies'] = @('dependencies', 'experimentalFeatures')
        $Mapping['DirectMSI'] = @('directMSI', 'experimentalFeatures')
        $Mapping['ZipInstall'] = @('zipInstall', 'experimentalFeatures')

        [String]$SettingsPath = "$($env:LOCALAPPDATA)\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
        #  Default value for settings.json
        [String]$JSON = '{"$schema":"https://aka.ms/winget-settings.schema.json"}'
        #  The default settings.json is invalid, and causes 5.1 ConvertFrom-Json to choke, so check/fix if needed.
        #  https://github.com/microsoft/winget-cli/blob/master/src/AppInstallerCommonCore/UserSettings.cpp
        if (Test-Path -LiteralPath $SettingsPath) {
            try {
                [String]$TryJSON = @(Get-Content -LiteralPath $SettingsPath | ForEach-Object { $_.Trim() } | Where-Object { (!([String]::IsNullOrWhiteSpace($_) -or $_ -like '//*')) }) -join ''
                $TryJSON = $TryJSON -replace ',}$', '}'
                $null = $TryJSON | ConvertFrom-Json
                $JSON = $TryJSON
            }
            catch {
                Write-Error "Unable to read settings from '$($SettingsPath)'"
                return
            }
        }
        $Settings = $JSON | ConvertFrom-Json

    }
    Process {
        foreach ($BParam in $PSBoundParameters.GetEnumerator()) {
            if ($Mapping.ContainsKey($BParam.Key)) {
                $UpdateJSON = $true
                $Map = $Mapping[$BParam.Key]
                $Name = $Map[0]
                $Value = $BParam.Value
                $JSPath = @($Map[1] -split '/')
                $PathCount = 1
                $SettingsWork = $Settings
                foreach ($Folder in $JSPath) {
                    $NoteMembers = @($SettingsWork | Get-Member | Where-Object { $_.MemberType -eq 'NoteProperty' } | Select-Object -ExpandProperty 'Name')
                    if ($NoteMembers -contains $Folder) {
                        $SettingsWork = $SettingsWork."$Folder"
                    }
                    else {
                        $null = $SettingsWork | Add-Member -MemberType NoteProperty -Name $Folder -Value ([pscustomobject]@{})
                        $SettingsWork = $SettingsWork."$Folder"
                    }
                }
                $NoteMembers = @($SettingsWork | Get-Member | Where-Object { $_.MemberType -eq 'NoteProperty' } | Select-Object -ExpandProperty 'Name')
                if ($NoteMembers -contains $Name) {
                    $SettingsWork."$Name" = $Value
                }
                else {
                    $null = $SettingsWork | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
                }
            }
            else {
                if ($BParam.Key -eq 'LocalManifestFiles') {
                    #  This setting is stored in a binary value in the appx local reg, for reasons, here:
                    #  C:\Users\atamido\AppData\Local\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\Settings
                    if ($LocalManifestFiles) {
                        $ParamArgString = '--Enable'
                    }
                    else {
                        $ParamArgString = '--Disable'
                    }
                    $WinGetArgs = "Settings", $ParamArgString, 'LocalManifestFiles', '--verbose-logs'
                    try {
                        #& "WinGet" $WingetArgs
                        $Process = Start-Process -FilePath 'winget.exe' -ArgumentList $WinGetArgs -NoNewWindow -PassThru -Wait
                        if ($Process.ExitCode -ne 0) {
                            Write-Error "Error calling 'winget $($WingetArgs -join ' ')' which returned exit code $($Process.ExitCode)"
                            return
                        }
                    }
                    catch {
                        Write-Error "Error calling 'winget $($WingetArgs -join ' ')'"
                        return
                    }
                }
                elseif ($IgnoreParams -contains $BParam.Key) {
                }
                else {
                    Write-Warning "Did not apply setting '$($BParam.Key)' with value '$($BParam.Value)'"
                }
            }
        }
    }
    End {
        if ($UpdateJSON) {
            $Settings | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $SettingsPath -Force -Encoding utf8
        }
        if ($Passthru) {
            return $Settings
        }
    }
}