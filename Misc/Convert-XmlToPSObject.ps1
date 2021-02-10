function Convert-XmlToPSObject ($Node){
    [String]$NodeType = $Node.NodeType
    [String]$Name = $Node.Name
    [String]$LocalName = $Node.LocalName

    if ($NodeType -eq 'Text') {
        [String]$Value = $Node.Value
        return (New-Object PSObject -Property @{Name = $Name; LocalName = $LocalName; NodeType = $NodeType; Value = $Value})
    } elseif ($NodeType -eq 'XmlDeclaration') {
        [String]$Version = $Node.Version
        [String]$Encoding = $Node.Encoding
        [String]$Standalone = $Node.Standalone
        return (New-Object PSObject -Property @{Name = $Name; LocalName = $LocalName; NodeType = $NodeType; Version = $Version; Encoding = $Encoding; Standalone = $Standalone})
    }

    $ChildNodes = @()

    if ($Node.HasChildNodes) {
        $ChildNodes = @($Node.ChildNodes | ForEach-Object {Convert-XmlToPSObject $_})
    }

    if ($NodeType -eq 'Document') {
        return (New-Object PSObject -Property @{Name = $Name; LocalName = $LocalName; NodeType = $NodeType; ChildNodes = $ChildNodes})
    }

    $Attributes = @{}

    if ($Node.HasAttributes) {
        foreach ($Attribute in $Node.Attributes) {
            $Attributes[($Attribute.Name)] = $Attribute.Value
        }
    }
    return (New-Object PSObject -Property @{Name = $Name; LocalName = $LocalName; NodeType = $NodeType; Attributes = $Attributes; ChildNodes = $ChildNodes})
}

