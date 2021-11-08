#  There are some environment variables, such as "firmware_type" which cannot be discovered normally programmatically.
#  This script attempts to discover additional variable through brute force.
#  On some older hardware, it's ~20 days to do all specified combinations up to 7 characters long.

#  Generally, it seems like environment variables are named with a-z, 0-9, "_", "-", "=", and ":".
#  However, they aren't supposed to contain "=", but do sometimes as the first character of a normal "hidden" variable.
#  And ":" only seems to happen after the first character.
#  So for the first character, we search for everything except ":"
#  And for following characters, we search for everything except "="


[Byte[]]$Bytes = @(0..31)

for ($i = 0; $i -lt $Bytes.Count; $i++) {
    $Bytes[$i] = 39
}


[Int]$ByteLength = 1
[Int]$CurrentByte = 0
[UInt64]$CountTried = 0
[Bool]$Loop = $true
$VarName = $null
$VarValue = $null


$Bytes[0] = 117
$Bytes[1] = 101
$Bytes[2] = 53
$Bytes[3] = 57
$Bytes[4] = 45
$Bytes[5] = 95
$Bytes[6] = 48
[Int]$ByteLength = 7


while ($true) {
    $CurrentByte = 0
    switch ($Bytes[$CurrentByte]) {
        41 { $Bytes[$CurrentByte] = 45 }
        45 { $Bytes[$CurrentByte] = 48 }
        57 { $Bytes[$CurrentByte] = 61 }
        61 { $Bytes[$CurrentByte] = 95 }
        95 { $Bytes[$CurrentByte] = 97 }
        122 {
            $Bytes[$CurrentByte] = 40
            $CurrentByte++
            if ($CurrentByte -eq $ByteLength) {
                $ByteLength++
            }
            $Loop = $true
            while ($Loop) {
                $Loop = $false
                switch ($Bytes[$CurrentByte]) {
                    41 { $Bytes[$CurrentByte] = 45 }
                    45 { $Bytes[$CurrentByte] = 48 }
                    58 { $Bytes[$CurrentByte] = 95 }
                    95 { $Bytes[$CurrentByte] = 97 }
                    122 {
                        $Bytes[$CurrentByte] = 40
                        $CurrentByte++
                        if ($CurrentByte -eq $ByteLength) {
                            $ByteLength++
                        }
                        $Loop = $true
                    }
                    default { $Bytes[$CurrentByte]++ }
                }
            }
        }
        default { $Bytes[$CurrentByte]++ }
    }
    $VarName = ([System.Text.Encoding]::ASCII.GetString($Bytes)).Substring(0, $ByteLength)
    $VarValue = [System.Environment]::GetEnvironmentVariable($VarName, 'Process')
    if (!($null -eq $VarValue)) {
        "'$($VarName)'='$($VarValue)'" | Out-File C:\Temp\Get-HiddenVariables.log -Append
        Write-Host "'$($VarName)'='$($VarValue)'"
    }
    $CountTried++
    if (($CountTried % 100000000) -eq 0) {
        Write-Host "Attempt $($CountTried), on '$($VarName)' at $(Get-Date)"
    }
}





