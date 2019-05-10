param (
    [Int]$CaptureSeconds = 300,
    [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
    [String]$ETLPath,
    [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
    [String]$ProcessesPath,
    [ValidateScript({Test-Path -LiteralPath $_ -PathType Leaf})]
    [String]$ClassesPath,
    [Switch]$VerboseEvents
)
#  Tracing and then viewing WMI events
#
#  Information about trace events available here:
#  https://docs.microsoft.com/en-us/windows/desktop/wmisdk/tracing-wmi-activity
#
#  Code snippets and ideas taken from:
#  Chentiangemalc
#  https://chentiangemalc.wordpress.com/2017/03/24/simple-wmi-trace-viewer-in-powershell/

[String]$StartTime = Get-Date -Format 'yyyyMMddHHmmss'
Start-Transcript "$($env:TEMP)\wmitrace-$($StartTime)-Transcript.log"

$Processes = @{}
$Events = @()

if ([String]::IsNullOrEmpty($ETLPath)) {
    Get-Process -IncludeUserName | ForEach-Object {$Processes["$($_.Id)"] = $_}
    $wmiLog = "Microsoft-Windows-WMI-Activity/Trace"
    echo y | Wevtutil.exe sl $wmiLog /e:true /ms:134217728
    Write-Host 'Collecting WMI trace data'
    Get-Process -IncludeUserName | ForEach-Object {$Processes["$($_.Id)"] = $_}
    #Read-Host -Prompt "Tracing WMI Started. Press [ENTER] to stop"
    Get-WmiObject win32_computersystemproduct | Out-Null
    Start-Sleep -Seconds $CaptureSeconds
    Wevtutil.exe sl $wmiLog /e:false
    Get-Process -IncludeUserName | ForEach-Object {$Processes["$($_.Id)"] = $_}
    Write-Host 'WMI trace ended'
    $Events = @(Get-WinEvent -LogName $wmiLog -Oldest | Where-Object {$null -notlike $_.Message -and $_.Message -ne 'Activity Transfer'})

    #  Backup data in case there is a crash, or want to further analyze
    Copy-Item -LiteralPath "$($env:windir)\System32\winevt\Logs\Microsoft-Windows-WMI-Activity%4Trace.etl" -Destination "$($env:TEMP)\wmitrace-$($StartTime)-Microsoft-Windows-WMI-Activity%4Trace.etl" -Verbose
    $TempProc = @{}
    $Processes.GetEnumerator() | ForEach-Object {$TempProc[$_.Name] = ($_.Value | Select-Object UserName,Name,Id)}
    $TempProc | ConvertTo-Json | Out-File -LiteralPath "$($env:TEMP)\wmitrace-$($StartTime)-Processes.json" -Verbose
    Remove-Variable TempProc
} else {
    $Events = @(Get-WinEvent -Path $ETLPath -Oldest | Where-Object {$null -notlike $_.Message -and $_.Message -ne 'Activity Transfer'})
}

if ($null -eq $Events -or $Events.Count -eq 0) {
    Write-Host "No WMI events in trace!"
} else {
    Write-Host "Captured $($Events.Count) WMI events"

    if (![String]::IsNullOrEmpty($ProcessesPath)) {
        (Get-Content -LiteralPath $ProcessesPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object {$Processes["$($_.Name)"] = $_.Value}
    }


    $Classes = @{}

    if ([String]::IsNullOrEmpty($ClassesPath)) {
        $Duplicates = @{}

        Write-Host 'Retrieving root namespaces'
        $Namespaces = Get-WmiObject -Namespace Root -Class __Namespace | Select-Object -ExpandProperty Name | Where-Object {$_ -ne 'directory'} | Sort-Object
        Write-Host "Retrieved $($Namespaces.Count + 1) root namespaces"

        Write-Host "Getting WMI classes from ROOT namespace"
        Get-WmiObject -List * -NameSpace ROOT | ForEach-Object {$Classes["$($_.Name)"] = "$($_.__NAMESPACE)"}

        Write-Host "Getting WMI classes from ROOT\directory namespace"
        Get-WmiObject -List * -NameSpace ROOT\directory | ForEach-Object {
            if($Classes.ContainsKey("$($_.Name)")){
                $Duplicates["$($_.Name)"] = 1
            } else {
                $Classes["$($_.Name)"] = "$($_.__NAMESPACE)"
            }
        }

        foreach ($Namespace in $Namespaces) {
            Write-Host "Getting WMI classes from ROOT\$($Namespace) namespace recursively"
            Get-WmiObject -List * -NameSpace "ROOT\$($Namespace)" -Recurse | ForEach-Object {
                if($Classes.ContainsKey("$($_.Name)")){
                    $Duplicates["$($_.Name)"] = 1
                } else {
                    $Classes["$($_.Name)"] = "$($_.__NAMESPACE)"
                }
            }
        }
        $Duplicates.Keys | ForEach-Object {$Classes.Remove($_)} | Out-Null
        Write-Host "Found $($Classes.Count) non-duplicate classes"

        $Classes | ConvertTo-Json | Out-File -LiteralPath "$($env:TEMP)\wmitrace-$($StartTime)-Classes.json" -Verbose
    } else {
        (Get-Content -LiteralPath $ClassesPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object {$Classes["$($_.Name)"] = $_.Value}
    }

    $Table = New-Object System.Data.DataTable
    [void]$Table.Columns.Add("Time")
    [void]$Table.Columns.Add("Namespace")
    [void]$Table.Columns.Add("Class")
    [void]$Table.Columns.Add("Type")
    [void]$Table.Columns.Add("OpID")
    [void]$Table.Columns.Add("Username")
    [void]$Table.Columns.Add("Process")
    [void]$Table.Columns.Add("Query")

    ForEach ($Event in $Events) {
        [String]$Time = $Event.TimeCreated.ToString('yyyy-MM-dd hh:mm:ss.fffffff')
        [String]$Username = ''
        [String]$Namespace = ''
        [String]$Class = ''
        [String]$OpID = ''
        [String]$Details = ''
        [String]$Type = ''
        [String]$Query = ''
        [String]$Namespace = ''
        [String]$Process = ''

        <#
        #  Determine values based on property count
        if ($Event.Properties.Count -notin @(6,8,11)) {
            Write-Warning "Unexpected number of event properties, $($Event.Properties.Count)."
            Write-Host $Event
            Write-Host $Event.Properties
            continue
        } elseif ($Event.Properties.Count -eq 6) {
            $Details =  $Event.Properties[1].Value.Trim()
            $Process = $Event.Properties[2].Value
        } elseif ($Event.Properties.Count -eq 8) {
            $Details =  $Event.Properties[3].Value.Trim()
            $Process = $Event.Properties[6].Value
            $Username = $Event.Properties[5].Value.Trim()
            $Namespace = $Event.Properties[7].Value.Trim()
        } else {
            $Details =  $Event.Properties[3].Value.Trim()
            $Process = $Event.Properties[7].Value
            $Username = $Event.Properties[6].Value.Trim()
            $Namespace = $Event.Properties[9].Value.Trim()
        }
        #>

        if ($Event.Properties.Count -eq 6) {
            $Process = $Event.Properties[2].Value
        } elseif ($Event.Properties.Count -eq 8) {
            $Process = $Event.Properties[6].Value
            $Namespace = $Event.Properties[7].Value.Trim()
            $Namespace = $Namespace -replace '^(\\\\\.\\ROOT\\|ROOT\\)',''
        } else {
            $Process = $Event.Properties[7].Value
            $Namespace = $Event.Properties[9].Value
            $Namespace = $Namespace -replace '^(\\\\\.\\ROOT\\|ROOT\\)',''
        }

        #  Break up Message string value into key/value pairs
        $Properties = @{}
        @($Event.Message -split ';') | ForEach-Object {
            [String[]]$r = @($_ -split '=')
            if ($r.Count -eq 2) {
                $r[0] = $r[0].Trim()
                $r[1] = $r[1].Trim()
                if(![String]::IsNullOrEmpty($r[0])){
                    $Properties["$($r[0])"]=[String]$r[1]
                }
            }
        }
        #  Common, easily parsable key/value pairs
        #  Be aware that there is no escaping of ;/= characters in the message string
        <#
        Name                           Value
        ----                           -----
        ErrorID                        0x0
        GroupOperationId               71117
        HostID                         6068
        Operation                      IWbemServices::Connect
        MethodName                     DoBFn
        ClientMachine                  C65981D76651A8
        OperationId                    71117
        ProviderGuid                   {661FF7F6-F4D1-4593-B59D-4C54C1ECE68B}
        NamespaceName                  131795202236574083
        Performing Update operation... 70235
        CorrelationId                  {00000000-0000-0000-0000-000000000000}
        User                           NT AUTHORITY\SYSTEM
        ClientProcessId                18316
        Flags                          0
        ClassName                      BFn
        ProviderInfo for GroupOpera... 71111
        ImplementationClass            BFn
        ResultCode                     0x0
        ProviderName                   WmiPerfClass
        Path                           C:\Windows\System32\wbem\WmiPerfClass.dll
        Stop OperationId               71117
        #>

        #  Find the property that lists the type of operation, and the query
        foreach ($Property in $Event.Properties) {
            if ($Property.Value -match '(^| )((IWbemServices|Provider)::[a-z0-9])+') {
                $Details = $Property.Value.Trim()
                break
            }
        }

        if ($Properties.ContainsKey('User')) {
            $Username = $Properties['User']
        }
        if ($Properties.ContainsKey('ClientProcessId')) {
            $Process = $Properties['ClientProcessId']
        }
        if ($Processes.ContainsKey("$Process")) {
            $Username = "$($Processes["$Process"].UserName)"
            $Process = "$($Processes["$Process"].Name) ($($Process))"
        }

        #  They Stop and Connect operations doesn't seem to be useful
        #  To view them, uncomment the two continue statements below
        if ($Properties.ContainsKey('Stop OperationId')) {
            if (!$VerboseEvents) {
                continue
            }
            $Type = 'Stop'
            $OpID = $Properties['Stop OperationId']
        } elseif ($Details -eq 'IWbemServices::Connect') {
            if (!$VerboseEvents) {
                continue
            }
            $Type = 'Connect'
            $OpID = $Properties['OperationId']
        } elseif ($Properties.ContainsKey('Performing Update operation on the WMI repository. OperationID')) {
            $Type = 'Update'
            $OpID = $Properties['Performing Update operation on the WMI repository. OperationID']
            $Query = $Properties['Operation']
        } elseif ([String]::IsNullOrEmpty($Details) -and $Properties.ContainsKey('Operation')) {
            $OpID = $Properties['OperationId']
            $Query = $Properties['Operation']
        } else {

            if ([String]::IsNullOrEmpty($Details)) {
                #  This message type doesn't appear to contain useful information
                if ($Event.Message -like 'CorrelationId = {00000000-0000-0000-0000-000000000000};*') {
                    Continue
                }
                Write-Warning 'Unknown event type'
                $Event.Message
                #$Event.Properties
            }

            if ($Properties.ContainsKey('GroupOperationId')) {
                $OpID = $Properties['GroupOperationId']
            } elseif ($Properties.ContainsKey('OperationId')) {
                $OpID = $Properties['OperationId']
            } elseif ($Properties.ContainsKey('ProviderInfo for GroupOperationId')) {
                $OpID = $Properties['ProviderInfo for GroupOperationId']
            } elseif ($Properties.ContainsKey('Stop OperationId')) {
                $OpID = $Properties['Stop OperationId']
            } elseif ($Properties.ContainsKey('Performing Update operation on the WMI repository. OperationID')) {
                $OpID = $Properties['Performing Update operation on the WMI repository. OperationID']
            }




            if (-not [String]::IsNullOrEmpty($Details)) {
                $TypeStart = $Details.IndexOf("::")+2
                $TypeEnd = $Details.IndexOf(" ",$TypeStart)
                $Type =$Details.Substring($TypeStart,$TypeEnd-$TypeStart)
                $Query = $Details.Substring($Details.IndexOf(":",$TypeEnd)+2)
            }

            if ($Properties.ContainsKey('ClassName')) {
                $Class = $Properties['ClassName']
            } elseif ($Type -in @('CreateClassEnum','CreateInstanceEnum','ExecMethod','GetObject') -and $Query -match '^([a-z0-9_]+).*$') {
                $Class = $Matches[1]
            } elseif ($Query -match '^.*from ([a-z0-9_]+).*$') {
                $Class = $Matches[1]
            }

            if ($Classes.ContainsKey($Class) -and [String]::IsNullOrWhiteSpace($Namespace)) {
                $Namespace = $Classes[$Class]
            }
            #  Remove the word "root" and other characters from the front of the Namespace name as it's redundant
            $Namespace = $Namespace -replace '^(\\\\\.\\ROOT\\|ROOT\\)',''

        }

        [void]$Table.Rows.Add(`
            $Time,`
            $Namespace,`
            $Class,`
            $Type,`
            $OpID,`
            $Username,`
            $Process,`
            $Query)

    }

    Write-Host "Filtered down to $(@($Table).Count) entries."
    $CSV = "$($env:TEMP)\wmitrace-$($StartTime).csv"
    Write-Output "Writing parsed trace information to $CSV"
    $Table | Export-Csv -NoTypeInformation -LiteralPath $CSV

    $Table | Out-GridView
}

Stop-Transcript