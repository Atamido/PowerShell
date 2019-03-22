
function Rename-TVEpisode {
    [cmdletbinding()]
    Param (
        [parameter(Mandatory=$true)]
        [String]$SeriesName,
        [parameter(Mandatory=$true)]
        [String]$FileStart,
        [parameter(Mandatory=$true)]
        [String]$Token,
        [parameter(Mandatory=$true)]
        [Int]$SeriesID,
        [parameter()]
        [Switch]$Rename
    )
    
    $Headers = @{Accept = 'application/json'; Authorization = "Bearer $($Token)"}
    $Episodes = @()
    $More = $true
    $Page = 1

    while ($More) {
        $Results = Invoke-RestMethod -Uri "https://api.thetvdb.com/series/$($SeriesID)/episodes?page=$($Page)" -Method Get -Headers $Headers
        $Episodes += ($Results).Data
        if ([String]::IsNullOrEmpty($Results.links.next)) {
            $More = $false
        }
        $Page++
    }

    #  Remove characters invalid for a Windows file name
    $null = $Episodes | ForEach-Object {$null = $_ | Add-Member -MemberType NoteProperty -Name 'EpisodeNameTrim' -Value (($_.episodeName -replace '[\/:*?"<>|]','').Trim())}
    $null = $Episodes | ForEach-Object {$null = $_ | Add-Member -MemberType NoteProperty -Name 'EpisodeNameTrimExtra' -Value (($_.EpisodeNameTrim -replace '\.',' ' -replace '[^a-z0-9 ]','').Trim())}
    $null = $Episodes | ForEach-Object {$null = $_ | Add-Member -MemberType NoteProperty -Name 'FileBaseName' -Value ("$($SeriesName) - S$("{0:00}" -f $_.airedSeason)E$("{0:00}" -f $_.airedEpisodeNumber) - $(($_.episodeName -replace ':','-' -replace '[\/:*?"<>|]','').Trim())")}
    
    $Episodes = $Episodes | Sort-Object -Property EpisodeName

    Write-Host "Found $($Episodes.Count) episodes"

    $Files = @(Get-ChildItem *.mkv | Where {$_.Name -like "$($FileStart)*"} | sort Name)

    for ($i = 0; $i -lt $Files.Count; $i++) {
        $File = $Files[$i]
        $Name = $File.BaseName
        $Extension = $File.Extension
        $FileName = $File.Name
        [String[]]$Titles = @()

        if ($Name -match "^$($FileStart) - s([0-9]{1,2})e([0-9]{1,2})`$") {
            $Season = [Int]($Matches[1])
            $EpisodeNum = [Int]($Matches[2])
            $Found = $null
            $Found = @($Episodes | Where-Object {$_.airedSeason -eq $Season -and $_.airedEpisodeNumber -eq $EpisodeNum})
            if ($Found) {
                $NewName = "$($Found[0].FileBaseName)$($Extension)"
                Write-Host "Renaming method 1: '$($FileName)' to '$($NewName)'"
                if ($Rename) {
                    Rename-Item $($FileName) -NewName $NewName
                }
                continue
            }
        }

        if ($Name -match "^$($FileStart) - s[0-9]{1,2}e[0-9]{1,2} - (.*)`$") {
            $Titles += $Matches[1]
        } else {
            $PairName = $Name  -replace "^.+? - '(.{5,})'.+?`$",'$1'
            $Titles += $PairName -split '_'
        }

        $TitleNum = 1
        foreach ($Title in $Titles) {
            $Found = @()
            $TitleExtra = ($Title -replace '\.',' ' -replace '[^a-z0-9 ]','').Trim()
            Write-Verbose "TitleExtra:           $($TitleExtra)"
            foreach ($Episode in $Episodes) {
                Write-Verbose "EpisodeName:          $($Episode.EpisodeName)"
                Write-Verbose "EpisodeNameTrim:      $($Episode.EpisodeNameTrim)"
                Write-Verbose "EpisodeNameTrimExtra: $($Episode.EpisodeNameTrimExtra)"
                if ($Episode.EpisodeNameTrim -eq $Title -or $Episode.EpisodeNameTrimExtra -eq $TitleExtra) {
                    $Found += $Episode
                    Write-Verbose "Found episode $($Episode.EpisodeNameTrim)"
                }
            }
            if ($Found.count -eq 1) {
                $NewName = "$($Found[0].FileBaseName)$($Extension)"
                if ($FileName -eq $NewName) {
                    Write-Host "Skipping correctly named '$($FileName)'"
                } else {
                    Write-Host "Renaming method 2: '$($FileName)' to '$($NewName)'"
                    if ($Rename) {
                        Rename-Item $($FileName) -NewName $NewName
                    }
                }
            } elseif ($Found.count -gt 1) {
                Write-Warning "Matched multiple episodes for '$($FileName)'"
                foreach ($F in $Found) {
                    Write-Warning "Matched: $($F.FileBaseName)"
                }
                break
            } else {
                [String[]]$TitleWords = @()
                $TitleWords += $Title -split ' ' | where {$_ -ne '-'}
                foreach ($Word in $TitleWords) {
                    $Found = @()
                    foreach ($Episode in $Episodes) {
                        if (($Episode.EpisodeNameTrim) -match "(^$Word )|( $Word`$)|( $Word )|(^$Word`$)") {
                            $Found += $Episode
                        }
                    }
                    if ($Found.count -eq 1) {
                        $NewName = "$($Found[0].FileBaseName)$($Extension)"
                        if ($FileName -eq $NewName) {
                            Write-Host "Skipping correctly named '$($FileName)'"
                        } else {
                            Write-Host "Renaming method 3:'$($FileName)' to '$($NewName)'"
                            if ($Rename) {
                                Rename-Item $($FileName) -NewName $NewName
                            }
                        }
                        break
                    }
                }
            }

            if ($Found.count -ne 1) {
                Write-Warning "Unable to match $($FileName)"
            }

            if ($Titles.Count -gt 1 -and $Titles.Count -gt $TitleNum) {
                $i++
                $TitleNum++
            }
        }
    }
}
