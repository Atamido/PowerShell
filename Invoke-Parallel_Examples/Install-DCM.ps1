Import-Module C:\tmp\Modules\Invoke-Parallel\Invoke-Parallel.psm1

$Results = Get-ChildItem C:\tmp\WMI | Where {(!($Installed.ContainsKey($_.Name)))} | ForEach-Object {-join[regex]::Matches($_.Name,".",'RightToLeft')} | Sort | ForEach-Object {-join[regex]::Matches($_,".",'RightToLeft')} |
Invoke-Parallel -RunspaceTimeout 1900 -Throttle 60 -ImportModules -ScriptBlock {
    $Computer = $_
    
    Try {
        $InstallState = Invoke-Command -ComputerName $Computer -ScriptBlock {
            If ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{DF0B9A53-C87D-49F9-95E3-AEAAC8C4D77B}') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{AC96949B-852D-464F-95DB-C9DDCD518BA8}'))
            {
                Return 'Installed'
            }

            If ((gwmi Win32_OperatingSystem).OSArchitecture -like '*64*')
            {
                $OS = 'x64'
            }
            Else
            {
                $OS = 'x86'
            }
            If (!(Test-Path -Path C:\temp -PathType Container))
            {
                New-Item -Path C:\ -Name Temp -ItemType Directory -Force | Out-Null
            }
            If (Test-Path -Path 'C:\temp\Command_Monitor_*.msi')
            {
                $Length = @(Get-ChildItem  -Path 'C:\temp\Command_Monitor_*.msi')[0].Length
                If ($Length -eq 24668672 -or $Length -eq 20467200)
                {
                    Return "$($OS),Copied"
                }
                Remove-Item 'C:\temp\Command_Monitor_*.msi' -Force
            }
            Return $OS
        }
    }
    Catch {
        Return "$($Computer),Unconnectable"
    }

    If ($InstallState -eq 'Installed')
    {
        Return "$($Computer),Installed"
    }

    
 
    Try {
        If ($InstallState -notlike '*Copied')
        {
            Try {
                $Session = New-PSSession $Computer
                $Installer = "Command_Monitor_$($InstallState).msi"
                Copy-Item -Path "C:\tmp\DCM\$($Installer)" -Destination 'C:\Temp'  -ToSession $Session | out-null
                #Copy-Item -Path "C:\tmp\DCM\$($Installer)" -Destination ('\\' + $Computer + '\c$\Temp')  -ToSession $Session
            }
            Catch {
                Return "$($Computer),Copyfailed"
            }
        }
        If ($InstallState -like 'x64*')
        {
            Invoke-Command -ComputerName $Computer -ScriptBlock {Start-Process 'msiexec.exe' -ArgumentList '/i C:\temp\Command_Monitor_x64.msi /qn'} | Out-Null
        }
        Else
        {
            Invoke-Command -ComputerName $Computer -ScriptBlock {Start-Process 'msiexec.exe' -ArgumentList '/i C:\temp\Command_Monitor_x86.msi /qn'} | Out-Null
        }
        Start-Sleep -Seconds 60
        $WMIStatus = Invoke-Command -ComputerName $Computer -ScriptBlock {Return ((Get-WmiObject -Namespace 'root' -Class '__Namespace' -Filter "Name = 'DCIM'") -and (Get-WmiObject -Namespace 'ROOT\DCIM\SYSMAN' -List | where {$_.name -like 'DCIM_BIOSPassword'}))}
        Return "$($Computer),$($WMIStatus)"
    }
    Catch {
        Return "$($Computer),Unconnectable"
    }

    Return "$($Computer),failed"
} 
