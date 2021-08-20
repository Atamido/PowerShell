
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
        [Parameter(Mandatory = $false, ParameterSetName = 'Default')]
        [Switch]
        $Shorten
    )

    Begin {
        [String]$KeyPath = ''
        [String]$KeyName = ''
        $RegRoots = @{}
        Get-PSDrive -PSProvider 'Registry' | ForEach-Object { $RegRoots[$_.Root] = $_.Name }
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
                $Key = Get-Item -LiteralPath $KeyPath
                $Properties = [System.Collections.Generic.List[PSCustomObject]]::new()
                foreach ($PropName in $Key.GetValueNames()) {
                    if ($IncludeType) {
                        $Property = [PSCustomObject]@{'Name' = $PropName; 'Type' = $Key.GetValueKind($Name); 'Value' = $Key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
                    }
                    else {
                        $Property = [PSCustomObject]@{'Name' = $PropName; 'Value' = $Key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
                    }
                    $Properties.Add($Property)
                }

                if ($IncludeEmpty -or $Properties.Count -gt 0) {
                    $KeyName = $Key.Name
                    if ($Shorten) {
                        #  Shorten key name to use PSDrive where possible
                        $Store = $Key.Name -replace '^([^:\\]+)(.*)', '$1'
                        if ($RegRoots.ContainsKey($Store)) {
                            $KeyName = "$($RegRoots[$Store]):$($Key.Name -replace '^([^:\\]+)(.*)', '$2')"
                        }
                    }
                    [PSCustomObject]@{'Key' = $KeyName; 'Props' = $Properties } | Write-Output
                }
            }
        }
    }
    End {
    }
}

