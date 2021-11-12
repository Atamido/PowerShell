function Convert-RegToPSObject {
    [CmdletBinding(DefaultParameterSetName = 'Default',
        PositionalBinding = $false)]
    [Alias()]
    [OutputType([String])]
    Param
    (
        #  Registry paths to export. Supports formats:
        #    HKLM:\
        #    HKEY_LOCAL_MACHINE\
        #    Pipeline output from Get-Item/Get-ChildItem
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $false,
            Position = 0,
            ParameterSetName = 'Default')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $LiteralPath,

        # Include registry keys with no properties
        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [Switch]
        $IncludeEmpty,

        # Include the type of each property
        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [Switch]
        $IncludeType,

        # Shorten the key name from 'HKEY_LOCAL_MACHINE\' to 'HKLM:\'
        # Change output properties from 'Name'='example','Value'='data' to 'example'='data'
        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [Switch]
        $Compress,

        # Include sub-keys
        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [Switch]
        $Recurse
    )

    Begin {
        [String]$KeyPath = ''
        [String]$KeyName = ''
        [String]$KeyPropName = ''
        [String]$KeyPropType = ''
        [String[]]$PropNames = @()
        $RegRoots = @{}
        Get-PSDrive -PSProvider 'Registry' | ForEach-Object { $RegRoots[$_.Root] = $_.Name }
        $Keys = [System.Collections.Generic.List[PSCustomObject]]::new()
    }
    Process {
        if ($Name) {
            $LiteralPath = $Name
            Write-Host 'found name'
        }
        foreach ($Path in $LiteralPath) {
            if ($Path -match '^[a-z]+:\\') {
                $KeyPath = $Path
            }
            else {
                $KeyPath = "Registry::$($Path)"
            }
            if (Test-Path -LiteralPath $KeyPath) {
                $Keys.Clear()
                $Keys.Add((Get-Item -LiteralPath $KeyPath))
                if ($Recurse) {
                    Get-ChildItem -LiteralPath $KeyPath -Recurse | ForEach-Object { $Keys.Add($_) }
                }
                foreach ($Key in $Keys) {
                    if ($Compress -and -not $IncludeType) {
                        $Properties = [PSCustomObject]@{}
                    }
                    else {
                        $Properties = [System.Collections.Generic.List[PSCustomObject]]::new()
                    }
                    $PropNames = $Key.GetValueNames() | Sort-Object
                    foreach ($PropName in $PropNames) {
                        #  The default registry value name comes back as blank, but if you want to set it you have to specify '(Default)'
                        if ($PropName -eq '') {
                            $KeyPropName = '(Default)'
                        }
                        else {
                            $KeyPropName = $PropName
                        }
                        $KeyPropValue = $Key.GetValue($PropName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

                        if ($IncludeType) {
                            $KeyPropType = $Key.GetValueKind($PropName).ToString();
                            if ($Compress) {
                                $Property = [PSCustomObject]@{"$KeyPropName" = $KeyPropValue; 'Type' = $KeyPropType }
                                $Properties.Add($Property)
                            }
                            else {
                                $Property = [PSCustomObject]@{'Name' = $KeyPropName; 'Value' = $KeyPropValue; 'Type' = $KeyPropType }
                                $Properties.Add($Property)
                            }
                        }
                        else {
                            if ($Compress) {
                                Add-Member -InputObject $Properties -MemberType NoteProperty -Name $KeyPropName -Value $KeyPropValue
                            }
                            else {
                                $Property = [PSCustomObject]@{'Name' = $KeyPropName; 'Value' = $KeyPropValue }
                                $Properties.Add($Property)
                            }
                        }

                    }

                    if ($IncludeEmpty -or $PropNames.Count -gt 0) {
                        $KeyName = $Key.Name
                        if ($Compress) {
                            #  Shorten key name to use PSDrive where possible
                            $Store = $Key.Name -replace '^([^:\\]+)(.*)', '$1'
                            if ($RegRoots.ContainsKey($Store)) {
                                $KeyName = "$($RegRoots[$Store]):$($Key.Name -replace '^([^:\\]+)(.*)', '$2')"
                            }
                        }
                        if ($Compress -and $PropNames.Count -eq 0) {
                            [PSCustomObject]@{'Key' = $KeyName } | Write-Output
                        }
                        else {
                            [PSCustomObject]@{'Key' = $KeyName; 'Props' = $Properties } | Write-Output
                        }
                    }
                }
            }
        }
    }
    End {
    }
}

<#
[String[]]$Keys = @(
    'HKU:\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization'
)

#  This is only needed if using a user registry hive
if (!(Test-Path -LiteralPath 'HKU:\')) {
    $null = New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS
}

$RegObs = Convert-RegToPSObject -LiteralPath $Keys -Recurse -Compress
#  Don't care about the usage key
$RegObs = $RegObs | Where-Object {$_.Key -notlike  '*Usage'}
#  Shorten the key name so they don't take as much space
$RegObs | ForEach-Object {$_.Key = $_.Key.Replace('HKU:\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization', '')}

$RegObs | ConvertTo-Json -Compress | Write-Output
#>