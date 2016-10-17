Import-Module C:\tmp\Modules\Invoke-Parallel\Invoke-Parallel.psm1

$Results = Get-Content .\computers.txt | Invoke-Parallel -RunspaceTimeout 250 -Throttle 150 -ImportModules -ScriptBlock {
    $ComputerName = $_
    $Result = ''
    $Result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        $Result = @(Get-WinEvent -ProviderName 'Microsoft-Windows-UserPnp' | where {$_.message -like 'Driver Management concluded the process to install driver e1d65x64.inf_amd64_2305982aeee58c7f\e1d65x64.inf*'})
        Return New-Object -TypeName psobject -Property @{eventlog=$Result;Connect=$true}
    }
    If([String]::IsNullOrEmpty($Result))
    {
        Return New-Object -TypeName psobject -Property @{PSComputerName=$ComputerName;eventlog=@();Connect=$false}
    }
    Return $Result
}

$Results
