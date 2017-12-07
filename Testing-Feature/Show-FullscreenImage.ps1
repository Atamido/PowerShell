param(
    [Parameter(Position=0)][ValidateSet('QA','PR','PROD')][String]$BuildEnv = 'PROD',
    [Parameter(Position=1)][String]$BackgroundRun = ''
)

Function Show-FullscreenImage {
    Param(
        [Parameter(Position=0)][ValidateScript({($_.Count -gt 0) -and ($_[0] -ne '')})][String[]]$Path,
        [Parameter(Position=1)][Bool]$Escapable = $true,
        [Parameter(Position=2)][float]$RefreshRate = 1
    )

    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 

    $objForm = New-Object System.Windows.Forms.Form
    $objForm.Text = "FirstUXWnd2"

    #  A convenient place to store a value from an event
    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = ''
    $Label.Visible = $false
    $objForm.Controls.Add($Label)

    # Add a trigger that closes the window via secondary method
    if ($Escapable) {
        $objForm.Add_KeyDown({
            if ($_.KeyCode -eq "Escape") {
                $Label.Text = 'Close'
            }
        })
    }
    
    $objForm.BackgroundImageLayout = 'Stretch'
    $LastWriteTime = (Get-Date).AddYears(-1100)

    foreach ($File in $Path) {
        if (Test-Path -Path $File -PathType Leaf) {
            if ($LastWriteTime -lt (Get-Item -Path $File).LastWriteTime) {
                try {
                    $Image = [System.Drawing.Bitmap]::new([System.Drawing.Bitmap]::FromFile($File))
                    $LastWriteTime = (Get-Item -Path $File).LastWriteTime
                    $objForm.BackgroundImage = $Image
                } catch {}
            }
        }
    }

    #$objForm.Topmost = $false
    $objForm.WindowState = 'Maximized'
    $objForm.FormBorderStyle = 'None'

    $Runspace = [runspacefactory]::CreateRunspace()
    $PowerShell = [System.Management.Automation.PowerShell]::Create()
    $PowerShell.runspace = $Runspace
    $Runspace.Open()

    [void]$PowerShell.AddScript({
        Param ($Param1)
        $Param1.ShowDialog()
    }).AddParameter('Param1',$objForm)

    $AsyncObject = $PowerShell.BeginInvoke()

    while($objForm.Visible -ne $true) {
        Start-Sleep 0.1
    }

    # Process things while the window sits there
    while($objForm.Visible -eq $True -and $Label.Text -ne 'Close') {
        foreach ($File in $Path) {
            if (Test-Path -Path $File -PathType Leaf) {
                if ($LastWriteTime -lt (Get-Item -Path $File).LastWriteTime) {
                    try {
                        $Image = [System.Drawing.Bitmap]::new([System.Drawing.Bitmap]::FromFile($File))
                        $LastWriteTime = (Get-Item -Path $File).LastWriteTime
                        $objForm.BackgroundImage = $Image
                        Write-Verbose "Loaded image $($File)"
                    } catch {}
                }
            }
        }
        Start-Sleep $RefreshRate
    }

    # Close the window if it isn't already closed
    if ($objForm.Visible -eq $True) {
        $objForm.Close()
    }

    [void]$PowerShell.EndInvoke($AsyncObject)
    [void]$PowerShell.Dispose()
}


#Show-FullscreenImage -Path "$($Env:TEMP)\DestImage.bmp","$($Env:TEMP)\DestImage2.bmp" -RefreshRate 0.1

#  If the script is launched without the backgroundrun parameter set, then the script will relaunch the script to run in the background
If ($BackgroundRun -eq '')
{
    if (@(Get-WmiObject Win32_Process -Filter "Name = 'powershell.exe' AND CommandLine LIKE '%$($MyInvocation.MyCommand.Name)%' AND ProcessId != '$($PID)'").Count -eq 0)
    {
        Start-Process powershell.exe -ArgumentList "-noprofile -nologo -ExecutionPolicy Unrestricted -windowstyle hidden -File `"$($MyInvocation.MyCommand.Path)`" -BuildEnv $($BuildEnv) -BackgroundRun Background"
    }
}
Else
{
    Start-Transcript
    Show-FullscreenImage
    Stop-Transcript
}

