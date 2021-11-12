<#
.Synopsis
   Combines information from the various firewall commandlets
.DESCRIPTION
   Uses the various firewall commandlets to add properties to the output of Get-NetFirewallRule
.EXAMPLE
   Get-NetFirewallRuleProperty -DisplayName SCCM* | FL *
.EXAMPLE
   Get-NetFirewallRuleProperty -DisplayName SCCM* -PolicyStoreSourceType GroupPolicy | Select DisplayName,Program,Protocol,LocalPort,Direction,Action,PolicyStoreSourceType,Profile
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   General notes
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   The role this cmdlet belongs to
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>
function Get-NetFirewallRuleProperty
{
    [CmdletBinding(DefaultParameterSetName='Parameter Set 1', 
                  SupportsShouldProcess=$true, 
                  PositionalBinding=$false,
                  ConfirmImpact='Medium')]
    [Alias()]
    [OutputType([PSCustomObject[]])]
    Param
    (
        # Param1 help description
        [Parameter(ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   #ValueFromRemainingArguments=$false, 
                   #Position=0,
                   ParameterSetName='Parameter Set 1')]
        [String[]]
        $Name = @(),

        # Param1 help description
        [Parameter(ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   #ValueFromRemainingArguments=$false, 
                   #Position=0,
                   ParameterSetName='Parameter Set 1')]
        [String[]]
        $DisplayName = @(),

        # Param1 help description
        [Parameter(ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   ValueFromRemainingArguments=$false, 
                   #Position=0,
                   ParameterSetName='Parameter Set 1')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('ActiveStore', 'ConfigurableServiceStore', 'PersistentStore', 'RSOP', 'StaticServiceStore', 'SystemDefaults')]
        [String]
        $PolicyStore = 'ActiveStore',

        # Param2 help description
        [Parameter(ParameterSetName='Parameter Set 1')]
        [ValidateSet('All', 'GroupPolicy', 'Local')]
        [String]
        $PolicyStoreSourceType = 'All'
    )

    if ($PolicyStoreSourceType -eq 'All') {
        $NetFirewallRules = @(Get-NetFirewallRule -PolicyStore $PolicyStore)
    } else {
        $NetFirewallRules = @(Get-NetFirewallRule -PolicyStore $PolicyStore -PolicyStoreSourceType $PolicyStoreSourceType)
    }

    if ($Name.Count -ne 0) {
        $NetFirewallRulesTemp = @()
        foreach ($N in $Name) {
            $NameMatches = @($NetFirewallRules | Where-Object {$_.Name -like $N})
            if ($NameMatches.Count -eq 0) {
                Write-Warning "Get-NetFirewallRule : No MSFT_NetFirewallRule objects found with property 'Name' equal to '$($N)'.  Verify the value of the property and retry."
            } else {
                $NetFirewallRulesTemp += $NameMatches
            }
        }
        $NetFirewallRules = $NetFirewallRulesTemp
    }

    if ($DisplayName.Count -ne 0) {
        $NetFirewallRulesTemp = @()
        foreach ($N in $DisplayName) {
            $RuleMatches = @($NetFirewallRules | Where-Object {$_.DisplayName -like $N})
            if ($RuleMatches.Count -eq 0) {
                Write-Warning "Get-NetFirewallRule : No MSFT_NetFirewallRule objects found with property 'DisplayName' equal to '$($N)'.  Verify the value of the property and retry."
            } else {
                $NetFirewallRulesTemp += $RuleMatches
            }
        }
        $NetFirewallRules = $NetFirewallRulesTemp
    }

    foreach ($NetFirewallRule in $NetFirewallRules) {
        $AddressFilter       = $NetFirewallRule | Get-NetFirewallAddressFilter
        $ApplicationFilter   = $NetFirewallRule | Get-NetFirewallApplicationFilter
        $InterfaceFilter     = $NetFirewallRule | Get-NetFirewallInterfaceFilter
        $InterfaceTypeFilter = $NetFirewallRule | Get-NetFirewallInterfaceTypeFilter
        $PortFilter          = $NetFirewallRule | Get-NetFirewallPortFilter
        $SecurityFilter      = $NetFirewallRule | Get-NetFirewallSecurityFilter
        $ServiceFilter       = $NetFirewallRule | Get-NetFirewallServiceFilter

        Add-Member -InputObject $NetFirewallRule -PassThru -NotePropertyMembers @{
                'AddressFilter' = $AddressFilter
                'LocalAddress'  = $AddressFilter.LocalAddress
                'RemoteAddress' = $AddressFilter.RemoteAddress
                'ApplicationFilter' = $ApplicationFilter
                'Program' = $ApplicationFilter.Program
                'Package' = $ApplicationFilter.Package
                'InterfaceFilter' = $InterfaceFilter
                'InterfaceAlias' = $InterfaceFilter.InterfaceAlias
                'InterfaceTypeFilter' = $InterfaceTypeFilter
                'InterfaceType' = $InterfaceTypeFilter.InterfaceType
                'PortFilter' = $PortFilter
                'Protocol' = $PortFilter.Protocol
                'LocalPort' = $PortFilter.LocalPort
                'RemotePort' = $PortFilter.RemotePort
                'IcmpType' = $PortFilter.IcmpType
                'DynamicTarget' = $PortFilter.DynamicTarget
                'SecurityFilter' = $SecurityFilter
                'Authentication' = $SecurityFilter.Authentication
                'Encryption' = $SecurityFilter.Encryption
                'OverrideBlockRules' = $SecurityFilter.OverrideBlockRules
                'LocalUser' = $SecurityFilter.LocalUser
                'RemoteUser' = $SecurityFilter.RemoteUser
                'RemoteMachine' = $SecurityFilter.RemoteMachine
                'ServiceFilter' = $ServiceFilter
                'Service' = $ServiceFilter.Service
            } | Write-Output
    }
}