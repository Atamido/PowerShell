
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
        $Name = $File.Name

        $PairName = $Name  -replace "^.+? - '(.{5,})'.+?`$",'$1'
        [String[]]$Titles = @()
        $Titles += $PairName -split '_'
        $TitleNum = 1
        foreach ($Title in $Titles) {
            $File = $Files[$i]
            $Name = $File.Name

            $Found = @()
            foreach ($Episode in $Episodes) {
                if ($Episode.episodeName -eq $Title) {
                    $Found += $Episode
                }
            }
            if ($Found.count -eq 1) {
                $NewName = "$($SeriesName) - S$("{0:00}" -f $Found[0].airedSeason)E$("{0:00}" -f $Found[0].airedEpisodeNumber) - $($Found[0].episodeName).mkv"
                Write-Host "Renaming '$($Name)' to '$($NewName)'"
                if ($Rename) {
                    Rename-Item $($Name) -NewName $NewName
                }
            }

            if ($Found.count -ne 1) {
                [String[]]$TitleWords = @()
                $TitleWords += $Title -split ' ' | where {$_ -ne '-'}
                foreach ($Word in $TitleWords) {
                    $Found = @()
                    foreach ($Episode in $Episodes) {
                        if ($Episode.episodeName -match "(^$Word )|( $Word`$)|( $Word )|(^$Word`$)") {
                            $Found += $Episode
                        }
                    }
                    if ($Found.count -eq 1) {
                        $NewName = "$($SeriesName) - S$("{0:00}" -f $Found[0].airedSeason)E$("{0:00}" -f $Found[0].airedEpisodeNumber) - $($Found[0].episodeName -replace ':','-').mkv"
                        Write-Host "Renaming '$($Name)' to '$($NewName)'"
                        if ($Rename) {
                            Rename-Item $($Name) -NewName $NewName
                        }
                        break
                    }
                }
            }

            if ($Found.count -ne 1) {
                Write-Warning "Unable to match $($Name)"
            }

            if ($Titles.Count -gt 1 -and $Titles.Count -gt $TitleNum) {
                $i++
                $TitleNum++
            }
        }
    }
}
