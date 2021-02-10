function Get-ExplorerProperty {
<#
.SYNOPSIS
Get the Windows Explorer properties for files and folders

.DESCRIPTION
Uses the Shell COM object to retreive the list of attributes available for filesystem items.
These attributes are the same attributes available in the Windows Explorer GUI columns.
The output of the function are System.IO.FileSystemInfo objects with two additional properties:
    ExplorerProperties: PSObject with each attribute as a standard property
    ExplorerPropertiesHash: Hashtable with the attribute as the key

Invalid values are not passed on through the function

.PARAMETER LiteralPath
A string, or array of strings of paths. These are the same paths accepted by Get-Item -LiteralPath

.PARAMETER FileSystemItems
Objects returned by Get-Item or Get-ChildItem

.PARAMETER Properties
The properties to be returned.  If left blank, most properties are returned, except those controlled by the IncludeAllProperties switch

.PARAMETER ExcludeProperties
The properties to exclude from being returned.

.PARAMETER IncludeAllProperties
Stop excluding these properties.  These properties are excluded by default as they contain values availabe via Get-Item
    Computer
    Date accessed
    Date created
    Date modified
    Filename
    Folder
    Folder name
    Folder path
    Item type
    Kind
    Name
    Path
    Space free
    Space used
    Total size
    Type

.EXAMPLE
PS C:\> Get-ChildItem $Env:USERPROFILE\Pictures -Recurse | Get-ExplorerProperty | Format-List Name,ExplorerProperties,ExplorerPropertiesHash

Name                   : Saved Pictures
ExplorerProperties     : @{Rating=Unrated; Shared=No; Attributes=RD; Sharing status=Private; Perceived type=Image; 
                         Owner=Contoso\atamido; Link status=Unresolved}
ExplorerPropertiesHash : {Rating, Shared, Attributes, Sharing status...}

Name                   : IMG_0035.JPG
ExplorerProperties     : @{Height=‎2448 pixels; Sharing status=Private; Metering mode=Pattern; File extension=.JPG; EXIF 
                         version=0221; Dimensions=‪3264 x 2448‬; Camera maker=Apple; Width=‎3264 pixels; Program name=9.2; 
                         Size=1.55 MB; ISO speed=ISO-320; Flash mode=No flash, auto; Shared=No; Exposure time=‎1/15 sec.; Vertical 
                         resolution=‎72 dpi; Exposure program=Normal; Attributes=A; Owner=Contoso\atamido; Link 
                         status=Unresolved; Horizontal resolution=‎72 dpi; Date taken=‎1/‎1/‎2016 ‏‎10:28 PM; Program mode=Normal 
                         program; Bit depth=24; White balance=Auto; 35mm focal length=29; F-stop=f/2.2; Rating=Unrated; 
                         Orientation=Normal; Camera model=iPhone 6; Exposure bias=‎0 step; Perceived type=Image; Focal length=‎4 
                         mm}
ExplorerPropertiesHash : {Height, Sharing status, Metering mode, File extension...}

.EXAMPLE
PS C:\> Get-ExplorerProperty $Env:USERPROFILE\Pictures -Properties 'Sharing status','Comments' | Format-List Name,ExplorerProperties


Name               : Pictures
ExplorerProperties : @{Comments=Contains digital photos, images, and graphic files.; Sharing status=Private}

.Credits
Written by Atamido

#>

    [cmdletbinding()]
    Param (
        [parameter()]
        [String[]]$Properties = @(),
        [parameter()]
        [String[]]$ExcludeProperties = @(),
        [parameter()]
        [Switch]$IncludeAllProperties,
        [parameter(ValueFromPipeline=$True,ParameterSetName='Items',Position=0)]
        [System.IO.FileSystemInfo[]]$FileSystemItems = @(),
        [parameter(ValueFromPipeline=$True,ParameterSetName='LiteralPath',Position=0)]
        [String[]]$LiteralPath = @()
    )

    begin {
        $Parents = @{}
        $ShellApplication = New-Object -ComObject "Shell.Application"
        $LimitProperties = $false
    }

    process {
        if ($Properties.Count -gt 0) {
            $LimitProperties = $true
        }

        if (-not ($IncludeAllProperties)) {
            $ExcludeProperties += @('Computer','Date accessed','Date created','Date modified','Filename','Folder','Folder name','Folder path','Item type','Kind','Name','Path','Space free','Space used','Total size','Type')
        }

        #  If LiteralPath was used, then convert the strings to FileSystemInfo objects
        #  and then validate they are valid paths
        if ($LiteralPath.Count -gt 0) {
            Write-Verbose "LiteralPath $($LiteralPath.Count)"
            [System.IO.FileSystemInfo[]]$FileSystemItems = @()
            $FileSystemItems = $LiteralPath | %{
                    if (Test-Path -LiteralPath ($_.Trim())){
                        $Item = Get-Item -LiteralPath ($_.Trim())
                        if ($Item.PSProvider.ToString() -eq 'Microsoft.PowerShell.Core\FileSystem') {
                            $Item
                        } else {
                            Write-Warning "This cmdlet only takes file system paths.  This path is a $($Item.PSProvider.ToString())"
                        }
                    } else {
                        Write-Warning "Invalid path: '$($_)'"
                    }
                }
        } else {
            Write-Verbose "FileSystemItems $($FileSystemItems.Count)"
            $FileSystemItems = $FileSystemItems | %{
                    if (Test-Path -LiteralPath ($_.FullName)){
                        $_
                    } else {
                        Write-Warning "Invalid path: '$($_.FullName)'"
                    }
                }
        }

        foreach ($Item in $FileSystemItems) {
            #  Determine the parent path.  
            #  This is needed because the Shell COM object needs the parent path
            #  In addition, this method can't be used to retrieve attributes on root paths
            if ($Item.FullName -eq $Item.Root) {
                Write-Warning "Unable to retrieve properties for root path: '$($Item.FullName)'"
                continue
            } elseif ($Item.PSIsContainer) {
                $ParentPath = Split-Path -LiteralPath $Item.FullName
            } else {
                $ParentPath = $Item.DirectoryName
            }

            Write-Verbose "Processing $($Item.FullName)"
            Write-Verbose "With parent path: '$ParentPath'"
            
            $ShellNamespace = $ShellApplication.NameSpace($ParentPath)

            #  The available attributes varies by folder, so each new parent folder needs to be queried to find available attributes
            if (-not ($Parents.ContainsKey($ParentPath))) {
                $Parent = @{}
                $Parent['Path'] = $ParentPath

                $Attributes = @{}

                for ($i = -1; $i -lt 1024; $i++) {
                    $PropName = $ShellNamespace.GetDetailsOf($null,$i)
                    if (-not $LimitProperties -and -not ([String]::IsNullOrWhiteSpace($PropName)) -and $ExcludeProperties -notcontains $PropName) {
                        $Attributes[$PropName] = $i
                    } elseif ($LimitProperties -and -not ([String]::IsNullOrWhiteSpace($PropName)) -and $Properties -contains $PropName) {
                        $Attributes[$PropName] = $i
                    }
                }

                Write-Verbose "Discovered $($Attributes.Count) attributes for parent '$ParentPath'"
                #Write-Verbose $Attributes
                $Parent['Attributes'] = $Attributes
                $Parents[$ParentPath] = $Parent
            } else {
                $Parent = $Parents[$ParentPath]
                $Attributes = $Parent['Attributes']
            }

            #  Query the file/folder for the attributes available in this filder
            $ExplorerProperties = @{}
            $FolderItem = $ShellNamespace.ParseName($Item.Name)
            foreach ($Attribute in $Attributes.GetEnumerator()) {
                $AttributeValue = $ShellNamespace.GetDetailsOf($FolderItem, $Attribute.Value)
                if ($AttributeValue) {
                    $ExplorerProperties[$Attribute.Key] = $AttributeValue
                }
            }
            
            Write-Verbose "Discovered $($ExplorerProperties.Count) attributes for item '$($Item.FullName)'"
            #Write-Verbose $ExplorerProperties
            $ExplorerPropertiesObj = New-Object -TypeName psobject -Property $ExplorerProperties
            Add-Member -InputObject $Item -NotePropertyMembers @{'ExplorerProperties' = $ExplorerPropertiesObj; 'ExplorerPropertiesHash' = $ExplorerProperties} -PassThru
        }
    }

    end {
        $null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ShellApplication)
    }
}