$Computers = Get-Content C:\tmp\Computers.txt | ForEach-Object {-join[regex]::Matches($_,".",'RightToLeft')} | Sort | ForEach-Object {-join[regex]::Matches($_,".",'RightToLeft')} | Out-File Computers2.txt


Import-Module C:\tmp\Modules\Invoke-Ping\Invoke-Ping.psm1
Get-Date
Measure-Command {
    $Responding = Invoke-Ping (Get-Content .\Computers2.txt) -quiet
}


Import-Module C:\tmp\Modules\Invoke-Parallel\Invoke-Parallel.psm1

Measure-Command {
$Results = Get-Content .\Computers2.txt |
Invoke-Parallel -RunspaceTimeout 150 -Throttle 250 -ImportModules -ScriptBlock {
    $ComputerName = $_
    Try {
        (New-Object System.Net.Sockets.TcpClient).connect("$($ComputerName).domainname.com",5986)
        Return New-Object –TypeName PSObject -Property @{'ComputerName'=$ComputerName;'TcpTestSucceeded'=$true}
    }
    Catch {
        Return New-Object –TypeName PSObject -Property @{'ComputerName'=$ComputerName;'TcpTestSucceeded'=$false}
    }
}
}
#$Results | Sort-Object ComputerName | Format-Table -Property ComputerName,TcpTestSucceeded




Import-Module C:\tmp\Modules\Invoke-Parallel\Invoke-Parallel.psm1
$computers = Get-Content .\vdi_freespace.txt
$results2 = $computers | Invoke-Parallel -LogFile 'C:\tmp\VDI\vdi.log' -RunspaceTimeout 120 -Throttle 100 -ImportModules -ScriptBlock {
    $Computer = $_
    Try {
        $Size = Invoke-Command -ComputerName $Computer -ScriptBlock {#$Size = (gwmi -Namespace root\ccm\softmgmtagent -Class cacheconfig).Size 
                $size = [Int]((Get-ChildItem 'C:\Users\*\Downloads\*' -Force -Recurse | Where-Object {$_.FullName -notlike 'C:\Users\Default*' -and $_.FullName -notlike 'C:\Users\All Users*'} | Measure-Object -Property Length -Sum).Sum/1MB)
                $Free = [int]((gwmi win32_logicaldisk | where {$_.deviceid -eq 'C:'}).Freespace/1MB)
                "$($Size),$($Free)"
            }
    }
    Catch
    {
    }
    Return "$($computer),$($Size)"
}

