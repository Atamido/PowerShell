Import-Module C:\tmp\Modules\Invoke-Parallel\Invoke-Parallel.psm1

$Completed = @{}
Get-ChildItem C:\tmp\HP\Other | %{$Completed[$_.Name] = ''}
Get-ChildItem C:\tmp\HP\Success | %{$Completed[$_.Name] = ''}
Get-ChildItem C:\tmp\HP\Connect | %{$Completed[$_.Name] = ''}
Get-ChildItem C:\tmp\HP\WMI | %{$Completed[$_.Name] = ''}
Get-ChildItem C:\tmp\HP\Investigate | %{$Completed[$_.Name] = ''}
$Computers = Get-Content C:\tmp\HP\HP-Store.txt | Where-Object {(!($Completed.ContainsKey($_)))}
Get-Date

$Results = $Computers | Invoke-Parallel -RunspaceTimeout 250 -Throttle 250 -ImportModules -ScriptBlock {
    $ComputerName = $_
    $Result = ''
    $Result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {

        #  Convert 8-bit ASCII string to EN-US keyboard scan code
        function Convert-ToKbdString
        {
            [CmdletBinding()]
            [OutputType([string])]
            Param
            (
                # Input, Type string, String to be encoded with EN Keyboard Scan Code Hex Values.
                [Parameter(Mandatory=$true,
                           Position=0)]
                [string]
                $UTF16String
            )
            $kbdHexVals=New-Object System.Collections.Hashtable

            $kbdHexVals."a"="1E"
            $kbdHexVals."b"="30"
            $kbdHexVals."c"="2E"
            $kbdHexVals."d"="20"
            $kbdHexVals."e"="12"
            $kbdHexVals."f"="21"
            $kbdHexVals."g"="22"
            $kbdHexVals."h"="23"
            $kbdHexVals."i"="17"
            $kbdHexVals."j"="24"
            $kbdHexVals."k"="25"
            $kbdHexVals."l"="26"
            $kbdHexVals."m"="32"
            $kbdHexVals."n"="31"
            $kbdHexVals."o"="18"
            $kbdHexVals."p"="19"
            $kbdHexVals."q"="10"
            $kbdHexVals."r"="13"
            $kbdHexVals."s"="1F"
            $kbdHexVals."t"="14"
            $kbdHexVals."u"="16"
            $kbdHexVals."v"="2F"
            $kbdHexVals."w"="11"
            $kbdHexVals."x"="2D"
            $kbdHexVals."y"="15"
            $kbdHexVals."z"="2C"
            $kbdHexVals."A"="9E"
            $kbdHexVals."B"="B0"
            $kbdHexVals."C"="AE"
            $kbdHexVals."D"="A0"
            $kbdHexVals."E"="92"
            $kbdHexVals."F"="A1"
            $kbdHexVals."G"="A2"
            $kbdHexVals."H"="A3"
            $kbdHexVals."I"="97"
            $kbdHexVals."J"="A4"
            $kbdHexVals."K"="A5"
            $kbdHexVals."L"="A6"
            $kbdHexVals."M"="B2"
            $kbdHexVals."N"="B1"
            $kbdHexVals."O"="98"
            $kbdHexVals."P"="99"
            $kbdHexVals."Q"="90"
            $kbdHexVals."R"="93"
            $kbdHexVals."S"="9F"
            $kbdHexVals."T"="94"
            $kbdHexVals."U"="96"
            $kbdHexVals."V"="AF"
            $kbdHexVals."W"="91"
            $kbdHexVals."X"="AD"
            $kbdHexVals."Y"="95"
            $kbdHexVals."Z"="AC"
            $kbdHexVals."1"="02"
            $kbdHexVals."2"="03"
            $kbdHexVals."3"="04"
            $kbdHexVals."4"="05"
            $kbdHexVals."5"="06"
            $kbdHexVals."6"="07"
            $kbdHexVals."7"="08"
            $kbdHexVals."8"="09"
            $kbdHexVals."9"="0A"
            $kbdHexVals."0"="0B"
            $kbdHexVals."!"="82"
            $kbdHexVals."@"="83"
            $kbdHexVals."#"="84"
            $kbdHexVals."$"="85"
            $kbdHexVals."%"="86"
            $kbdHexVals."^"="87"
            $kbdHexVals."&"="88"
            $kbdHexVals."*"="89"
            $kbdHexVals."("="8A"
            $kbdHexVals.")"="8B"
            $kbdHexVals."-"="0C"
            $kbdHexVals."_"="8C"
            $kbdHexVals."="="0D"
            $kbdHexVals."+"="8D"
            $kbdHexVals."["="1A"
            $kbdHexVals."{"="9A"
            $kbdHexVals."]"="1B"
            $kbdHexVals."}"="9B"
            $kbdHexVals.";"="27"
            $kbdHexVals.":"="A7"
            $kbdHexVals."'"="28"
            $kbdHexVals."`""="A8"
            $kbdHexVals."``"="29"
            $kbdHexVals."~"="A9"
            $kbdHexVals."\"="2B"
            $kbdHexVals."|"="AB"
            $kbdHexVals.","="33"
            $kbdHexVals."<"="B3"
            $kbdHexVals."."="34"
            $kbdHexVals.">"="B4"
            $kbdHexVals."/"="35"
            $kbdHexVals."?"="B5"

            $kbdEncodedString=""
            foreach ($char in $UTF16String.ToCharArray())
            {
                $kbdEncodedString+=$kbdHexVals.Get_Item($char.ToString())
            }
            return $kbdEncodedString
        }

        $ReturnObject = New-Object -TypeName PSObject -Property @{'WMI'=$false;'Success'=$false;'PWChange'=$false;'PWAdd'=$false}
        [Bool]$Success = $false
        [String[]]$Passwords = @('32 33 34',
                                    '35 36 37') | %{$password = ''; $_.split()| %{$password += ([char][int]$("0x{0}" -f $_)) }; $password}
        [String]$NewPassword = ('38 39 40'.Split() | %{([char][int]$("0x{0}" -f $_)) }) -join ''

        $ErrorActionPreference = 'SilentlyContinue'

        [Bool]$Success = $false
        [Bool]$TempSuccess = $false


        #  Make sure the manufacturer's WMI namespace and classes are available
        If ((Get-WmiObject -Namespace 'root' -Class '__Namespace' -Filter "Name = 'HP'") -and (Get-WmiObject -Namespace 'ROOT\HP\InstrumentedBIOS' -List | where {$_.name -like 'HP_BIOSSettingInterface'}))
        {
            $ReturnObject.WMI = $true
            #  See if need to use the UTF-16 encoding style
            [Bool]$kbd = $true
            If (((Get-WmiObject -Namespace 'ROOT\HP\InstrumentedBIOS' -Class 'HP_BIOSSetting') | Where-Object -FilterScript {$_.Name -eq 'Setup Password'}).SupportedEncoding[0] -eq 'utf-16')
            {
                $kbd = $false
            }
            #  IsSet '1' is BIOS password set, and '0' is not set, apparently
            If ((Get-WmiObject -Namespace 'root\HP\InstrumentedBIOS' -Class 'HP_BIOSSetting' -Filter "Name = 'Setup Password'").IsSet -eq 1)
            {

                ForEach ($Password in $Passwords)
                {
                    If (!($Success))
                    {
                        If ($kbd)
                        {
                            $WmiResult = (Get-WmiObject -Namespace 'ROOT\HP\InstrumentedBIOS' -Class 'HP_BIOSSettingInterface').SetBIOSSetting('Setup Password', "<kbd/>$(Convert-ToKbdString $NewPassword)", "<kbd/>$(Convert-ToKbdString $Password)")
                        }
                        Else
                        {
                            $WmiResult = (Get-WmiObject -Namespace 'ROOT\HP\InstrumentedBIOS' -Class 'HP_BIOSSettingInterface').SetBIOSSetting('Setup Password', "<utf-16/>$($NewPassword)", "<utf-16/>$($Password)")
                        }
                        If ($WmiResult.Return -eq '0')
                        {
                            $Success = $true
                            If ($Password -ne $NewPassword)
                            {
                                $ReturnObject.PWChange = $true
                            }
                        }
                    }
                }
            }
            Else
            {
                If ($kbd)
                {
                    $WmiResult = (Get-WmiObject -Namespace 'ROOT\HP\InstrumentedBIOS' -Class 'HP_BIOSSettingInterface').SetBIOSSetting('Setup Password', "<kbd/>$(Convert-ToKbdString $NewPassword)", "<kbd/>")
                }
                Else
                {
                    $WmiResult = (Get-WmiObject -Namespace 'ROOT\HP\InstrumentedBIOS' -Class 'HP_BIOSSettingInterface').SetBIOSSetting('Setup Password', "<utf-16/>$($NewPassword)", "<utf-16/>")
                }
                If ($WmiResult.Return -eq '0')
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
        New-Item -Name $ComputerName -Path C:\tmp\HP\Connect -ItemType File -Force
    }
    ElseIf ($Result.WMI -eq $false)
    {
        New-Item -Name $ComputerName -Path C:\tmp\HP\WMI -ItemType File -Force
    }
    ElseIf ($Result.Success -eq $false)
    {
        New-Item -Name $ComputerName -Path C:\tmp\HP\Success -ItemType File -Force
    }
    ElseIf ($Result.Success -eq $true)
    {
        New-Item -Name $ComputerName -Path C:\tmp\HP\Other -ItemType File -Force
    }
    Else
    {
        New-Item -Name $ComputerName -Path C:\tmp\HP\Investigate -ItemType File -Force
    }
    #Write-Host $Result
    Return $Result
}
Get-Date