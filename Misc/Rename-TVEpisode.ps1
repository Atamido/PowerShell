
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

    Write-Host "Found $($Episodes.Count) episodes"

    $Files = @(Get-ChildItem *.mkv | Where {$_.Name -like "$($FileStart)*"} | sort Name)

    for ($i = 0; $i -lt $Files.Count; $i++) {
        $File = $Files[$i]
        $Name = $File.BaseName
        $FileName = $File.Name
        [String[]]$Titles = @()

        if ($Name -match "^$($FileStart) - s[0-9]{1,2}e[0-9]{1,2} - (.*)`$") {
            $Titles += $Matches[1]
        } else {
            $PairName = $Name  -replace "^.+? - '(.{5,})'.+?`$",'$1'
            $Titles += $PairName -split '_'
        }

        $TitleNum = 1
        foreach ($Title in $Titles) {
            $File = $Files[$i]
            $Name = $File.BaseName

            $Found = @()
            foreach ($Episode in $Episodes) {
                #  Remove characters invalid for a Windows file name
                $EpisodeName = $Episode.episodeName -replace '[\/:*?"<>|]',''
                if ($EpisodeName -eq $Title) {
                    $Found += $Episode
                }
            }
            if ($Found.count -eq 1) {
                $NewName = "$($SeriesName) - S$("{0:00}" -f $Found[0].airedSeason)E$("{0:00}" -f $Found[0].airedEpisodeNumber) - $($Found[0].episodeName -replace '[\/:*?"<>|]','').mkv"
                if ($FileName -eq $NewName) {
                    Write-Host "Skipping correctly named '$($FileName)'"
                } else {
                    Write-Host "Renaming '$($FileName)' to '$($NewName)'"
                    if ($Rename) {
                        Rename-Item $($FileName) -NewName $NewName
                    }
                }
            }

            if ($Found.count -ne 1) {
                [String[]]$TitleWords = @()
                $TitleWords += $Title -split ' ' | where {$_ -ne '-'}
                foreach ($Word in $TitleWords) {
                    $Found = @()
                    foreach ($Episode in $Episodes) {
                        if (($Episode.episodeName -replace '[\/:*?"<>|]','') -match "(^$Word )|( $Word`$)|( $Word )|(^$Word`$)") {
                            $Found += $Episode
                        }
                    }
                    if ($Found.count -eq 1) {
                        $NewName = "$($SeriesName) - S$("{0:00}" -f $Found[0].airedSeason)E$("{0:00}" -f $Found[0].airedEpisodeNumber) - $($Found[0].episodeName -replace ':','-' -replace '[\/:*?"<>|]','').mkv"
                        if ($FileName -eq $NewName) {
                            Write-Host "Skipping correctly named '$($FileName)'"
                        } else {
                            Write-Host "Renaming '$($FileName)' to '$($NewName)'"
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
