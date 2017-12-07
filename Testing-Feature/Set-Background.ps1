Function Set-Background {
    Param(
        [Parameter(Position=0)][ValidateScript({($_ -eq '') -or (Test-Path $_ -PathType Leaf)})][String]$Path = '-1',
        [Parameter(Position=1)][ValidateSet('Center','Fill','Fit','Stretch','Tile')][String]$Style = 'None',
        [Parameter(Position=2)][ValidateRange(0,16777215)][Int]$Color = -1
    )

    if ($Style -ne 'None') {
        Switch ($Style) {
            'Center' {
                $TileWallpaper = '0'
                $WallpaperStyle = '0'
            }
            'Fill' {
                $TileWallpaper = '0'
                $WallpaperStyle = '10'
            }
            'Fit' {
                $TileWallpaper = '0'
                $WallpaperStyle = '6'
            }
            'Stretch' {
                $TileWallpaper = '0'
                $WallpaperStyle = '2'
            }
            'Tile' {
                $TileWallpaper = '1'
                $WallpaperStyle = '0'
            }
        }

        if (-not (Test-Path -Path 'HKCU:\Control Panel\Desktop' -PathType Container)){
            New-Item -Name 'Desktop' -Path 'HKCU:\Control Panel' -Force | Out-Null
        }

        New-ItemProperty -Name 'TileWallpaper' -Value $TileWallpaper -Path 'HKCU:\Control Panel\Desktop' -PropertyType String -Force | Out-Null
        New-ItemProperty -Name 'WallpaperStyle' -Value $WallpaperStyle -Path 'HKCU:\Control Panel\Desktop' -PropertyType String -Force | Out-Null
    }

    Try {
        $MethodDefinition = @'
            [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
            public static extern int SystemParametersInfo (int uAction, int uParam, string lpvParam, int fuWinIni);
            [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
            public static extern bool SetSysColors(int cElements, int [] lpaElements, int [] lpaRgbValues);
'@

        if (-not ([System.Management.Automation.PSTypeName]'User32.SetBackground').Type) {
            Add-Type -MemberDefinition $MethodDefinition -Name 'SetBackground' -Namespace 'User32' | Out-Null
        }
        
        if ($Color -ne -1) {
            [Win32.SetBackground]::SetSysColors(1, 1, $Color) | Out-Null
        }
        if ($Path -ne '-1') {
            [User32.SetBackground]::SystemParametersInfo(20, 0, $Path, 0x01) | Out-Null
        }

    } Catch {
        Write-Warning -Message "Failed because $($_.Exception.Message)"
    }
}

Set-Background -Path '.\Untitled.bmp' -Style Center -Color 0xff00ff

