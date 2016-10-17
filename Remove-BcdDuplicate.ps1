<#
This script checks for duplicate "Windows Boot Manager" entries in the UEFI firmware and deletes them.


#  Example output from bcedit


Firmware Boot Manager
---------------------
identifier              {fwbootmgr}
displayorder            {bootmgr}
                        {5a73f377-0d86-11e6-93e6-204747f1714e}
                        {e679572f-0e1b-11e6-9356-806e6f6e6963}
                        {e6795730-0e1b-11e6-9356-806e6f6e6963}
                        {e6795731-0e1b-11e6-9356-806e6f6e6963}
timeout                 2

Windows Boot Manager
--------------------
identifier              {bootmgr}
device                  partition=\Device\HarddiskVolume2
path                    \EFI\Microsoft\Boot\bootmgfw.efi
description             Windows Boot Manager
locale                  en-US
inherit                 {globalsettings}
default                 {current}
resumeobject            {5a73f36f-0d86-11e6-93e6-204747f1714e}
displayorder            {current}
toolsdisplayorder       {memdiag}
timeout                 30

Firmware Application (101fffff)
-------------------------------
identifier              {5a73f375-0d86-11e6-93e6-204747f1714e}
path                    \EFI\Microsoft\Boot\bootmgfw.efi
description             Windows Boot Manager

Firmware Application (101fffff)
-------------------------------
identifier              {5a73f376-0d86-11e6-93e6-204747f1714e}
path                    \EFI\Microsoft\Boot\bootmgfw.efi
description             Windows Boot Manager

Firmware Application (101fffff)
-------------------------------
identifier              {5a73f377-0d86-11e6-93e6-204747f1714e}
description             Windows Boot Manager

Firmware Application (101fffff)
-------------------------------
identifier              {e679572f-0e1b-11e6-9356-806e6f6e6963}
description             Onboard NIC(IPV4)

Firmware Application (101fffff)
-------------------------------
identifier              {e6795730-0e1b-11e6-9356-806e6f6e6963}
description             Onboard NIC(IPV6)

Firmware Application (101fffff)
-------------------------------
identifier              {e6795731-0e1b-11e6-9356-806e6f6e6963}
device                  partition=D:
description             UEFI: SanDisk



#>

# Set Script file path variables
$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptName = $MyInvocation.MyCommand.Name
$ScriptExt = (Get-Item $ScriptPath).extension
$ScriptBaseName = $ScriptName -replace($ScriptExt ,"")
$ScriptFolder = Split-Path -parent $ScriptPath

# Import TSUtility module
Import-Module "$ScriptFolder\TSUtility.psm1" -Force

#  Run BCDEdit and capture its textual output
[String[]]$Firmware = & bcdedit /enum firmware
#  Line number in an individual section
[Int32]$LineNum = -1
#  Section type
[String]$Set = ''
#  GUID of an section
[String]$Guid = ''
#  All entries in UEFI that are not the default bootmgr
$Entries = @{}
#  List of entries in UEFI that are selected for boot
[String[]]$DisplayOrder = @()
#  Have any settings been changed
[Bool]$FirmwareSettingsUpdated = $false
#  Is the system in a task sequence
[Bool]$InTS = $true

#  Test if system is in a task sequence
Try
{
    $TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
}
Catch
{
    Write-Verbose 'Not running in a Task Sequence'
    $InTS = $false
}

#  Examine each line from the BCDEdit output
ForEach ($Line in $Firmware)
{
    #  Has any valid section been reached
    If ($LineNum -gt -1)
    {
        $LineNum++
    }

    #  Each section starts with a series of hyphens.  This checks for that.
    If ($Line -match '^----*$')
    {
        #  Line zero of the new section
        $LineNum = 0
        $Set = ''
        $Guid = ''
    }
    ElseIf ($LineNum -eq 1)
    {
        #  Detect Firmware Boot Manager section 
        If ($Line -imatch '\{fwbootmgr\}$')
        {
            $Set = 'fwbootmgr'
        }
        #  Detect current default Windows Boot Manager section
        ElseIf ($Line -imatch '\{bootmgr\}$')
        {
            $Set = 'bootmgr'
        }
        #  Detect additional "Firmware Application" section is detected by the presence of a GUID
        ElseIf ($Line -imatch '\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}$')
        {
            $Guid = $Matches[0]
            $Set = 'entry'
            $Entries[$Guid] = @($Guid, '')
        }
        Else
        {
            Out-TSLogEntry -LogMsg "Unknown type $($Line)" -LogType LogTypeInfo
            $Set = ''
        }
    }
    #  Currently in a valid section
    ElseIf ($Set -ne '')
    {
        #  Currently in a valid Firmware Boot Manager section 
        If ($Set -eq 'fwbootmgr')
        {
            #  Detect GUID.  GUIDs in the FBM all appear to be from the display order, which we are keeping because it might be useful
            If ($Line -imatch '\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}$')
            {
                $DisplayOrder += $Matches[0]
            }
        }
        #  Currently in Windows Boot Manager section
        ElseIf ($Set -eq 'bootmgr')
        {
            #  Do we need anything from this?
        }
        #  Currently in a Firmware Application section
        ElseIf ($Set -eq 'entry')
        {
            #  Description text.  This value is localized and will be different in French
            If ($Line -imatch '^description [ ]*(.*)$')
            {
                #  Don't overwrite an existing entry
                If ($Entries[$Guid][1] -eq '')
                {
                    $Entries[$Guid] = @($Guid, $Matches[1])
                }
            }
            #  This path or description should only be in Windows Boot Manager entries
            ElseIf ($Line -imatch '\\EFI\\Microsoft\\Boot\\bootmgfw\.efi$' -or $Line -imatch 'Windows Boot Manager$')
            {
                $Entries[$Guid] = @($Guid, 'Windows Boot Manager')
            }
            #  Onboard Dell NICs start with "Onboard"
            ElseIf ($Line -imatch 'Onboard .*$')
            {
                $Entries[$Guid] = @($Guid, $Matches[0])
            }
            #  Plugged in bootable USB device begins with UEFI
            ElseIf ($Line -imatch 'UEFI: .*$')
            {
                $Entries[$Guid] = @($Guid, $Matches[0])
            }
        }
    }
}

Out-TSLogEntry -LogMsg "$($Entries.Count) BCD Entries other than {bootmgr}" -LogType LogTypeInfo

#  Iterate through the Firmware Application sections that were found
ForEach ($BCDEntry in $Entries.Values)
{
    #  If the section is a Windows Boot Manager section, then delete it
    If ($BCDEntry[1] -eq 'Windows Boot Manager')
    {
        Out-TSLogEntry -LogMsg "Deleting $($BCDEntry[0]), $($BCDEntry[1])" -LogType LogTypeInfo
        & bcdedit /delete $BCDEntry[0]
        $FirmwareSettingsUpdated = $true
    }
    Else
    {
        Out-TSLogEntry -LogMsg "Skipping $($BCDEntry[0]), $($BCDEntry[1])" -LogType LogTypeInfo
    }
}

#  If the firmware was changed, and we're in a task sequence, set a task sequence variable
If ($FirmwareSettingsUpdated -and $InTS)
{
    Out-TSLogEntry -LogMsg "Setting FirmwareSettingsUpdated to 'true'" -LogType LogTypeInfo
    $TSEnv.Value('FirmwareSettingsUpdated') = 'true'
}
