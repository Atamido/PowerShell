Import-Module C:\tmp\Modules\Invoke-Parallel\Invoke-Parallel.psm1

$Completed = @{}
Get-ChildItem C:\tmp\Other | %{$Completed[$_.Name] = ''}
Get-ChildItem C:\tmp\Success | %{$Completed[$_.Name] = ''}
Get-ChildItem C:\tmp\Connect | %{$Completed[$_.Name] = ''}
Get-ChildItem C:\tmp\WMI | %{$Completed[$_.Name] = ''}
Get-ChildItem C:\tmp\Investigate | %{$Completed[$_.Name] = ''}
$Computers = Get-Content C:\tmp\Dell-Store.txt | Where-Object {(!($Completed.ContainsKey($_)))}
Get-Date

$Results = $Computers | Invoke-Parallel -RunspaceTimeout 150 -Throttle 250 -ImportModules -ScriptBlock {
    $ComputerName = $_
    $Result = ''
    $Result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        $ReturnObject = New-Object -TypeName PSObject -Property @{'WMI'=$false;'Success'=$false;'PWChange'=$false;'PWAdd'=$false}
        [Bool]$Success = $false
        [String[]]$Passwords = @('32 33 34',
                                    '35 36 37') | %{$password = ''; $_.split()| %{$password += ([char][int]$("0x{0}" -f $_)) }; $password}
        [String]$NewPassword = ('38 39 40'.Split() | %{([char][int]$("0x{0}" -f $_)) }) -join ''

        $ErrorActionPreference = 'SilentlyContinue'
        If ((Get-WmiObject -Namespace 'root' -Class '__Namespace' -Filter "Name = 'DCIM'") -and (Get-WmiObject -Namespace 'ROOT\DCIM\SYSMAN' -List | where {$_.name -like 'DCIM_BIOSPassword'}))
        {
            $ReturnObject.WMI = $true
            If ((Get-WmiObject -Namespace "ROOT\DCIM\SYSMAN" -Class "DCIM_BIOSPassword" | Where-Object {$_.AttributeName -eq 'AdminPwd'}).IsSet)
            {
                $WmiResult = (Get-WmiObject -Namespace 'root\dcim\sysman' -Class 'DCIM_BIOSService').SetBIOSAttributes($null, $null, 'Strong Password', '1', $NewPassword)
                If ($WmiResult.ReturnValue -eq 'Success' -or $WmiResult.ReturnValue -eq 0)
                {
                    $Success = $true
                }
            
                ForEach ($Password in $Passwords)
                {
                    If (!($Success))
                    {
                        $WmiResult = (Get-WmiObject -Namespace "ROOT\DCIM\SYSMAN" -Class "DCIM_BIOSService").SetBIOSAttributes($null, $null, 'AdminPwd', $NewPassword, $Password, $null)
                        If ($WmiResult.ReturnValue -eq 'Success' -or $WmiResult.ReturnValue -eq 0)
                        {
                            $Success = $true
                            $ReturnObject.PWChange = $true
                        }
                    }
                }
            }
            Else
            {
                $WmiResult = (Get-WmiObject -Namespace "ROOT\DCIM\SYSMAN" -Class "DCIM_BIOSService").SetBIOSAttributes($null, $null, 'AdminPwd', $NewPassword, '', $null)
                If ($WmiResult.ReturnValue -eq 'Success' -or $WmiResult.ReturnValue -eq 0)
                {
                    $Success = $true
                    $ReturnObject.PWAdd = $true
                }
            }
            $ReturnObject.Success = $Success
        }
        Return $ReturnObject
    }
    If ($Result -eq $null)
    {
        New-Item -Name $ComputerName -Path C:\tmp\Connect -ItemType File -Force
    }
    ElseIf ($Result.WMI -eq $false)
    {
        New-Item -Name $ComputerName -Path C:\tmp\WMI -ItemType File -Force
    }
    ElseIf ($Result.Success -eq $false)
    {
        New-Item -Name $ComputerName -Path C:\tmp\Success -ItemType File -Force
    }
    ElseIf ($Result.Success -eq $true)
    {
        New-Item -Name $ComputerName -Path C:\tmp\Other -ItemType File -Force
    }
    Else
    {
        New-Item -Name $ComputerName -Path C:\tmp\Investigate -ItemType File -Force
    }
    #Write-Host $Result
    Return $Result
}
Get-Date
#$Results | Export-Csv -NoTypeInformation c:\tmp\Dell_Results.csv
