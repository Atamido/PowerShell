function Get-CMDependency {
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String[]]$LocalizedDisplayName = @(),
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String[]]$ModelName = @(),
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [String]$ComputerName,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [hashtable]$Results = @{},
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Bool]$Recurse = $true
    )
    
    #  Initialize variables
    $FilteredApps = @()
    [String[]]$Selections = @()
    [String[]]$Filters = @()

    #  Create WMI filters based on the entered display name or unique ID
    if ($LocalizedDisplayName.Count -gt 0) {
        foreach ($Name in $LocalizedDisplayName) {
            $Filters += "LocalizedDisplayName LIKE '$($Name)'"
        }
    } else {
        foreach ($Name in $ModelName) {
            $Filters += "ModelName LIKE '$($Name)'"
        }
    }

    #  Query WMI for each of the objects
    foreach ($Filter in $Filters) {
        $WMIResult = @()
        try {
            $WMIResult += @(Get-WmiObject -ComputerName $ComputerName -Namespace "root\sms\site_cas" -class SMS_Application -Filter $Filter)
        } catch {
            Write-Error "Failed to query WMI for application with filter '$($Filter)'"
        }

        #  Throw a warning if applications aren't found
        if ($WMIResult.Count -eq 0) {
            Write-Warning "No applications found with filter '$($Filter)'"
        }
        $FilteredApps += $WMIResult
    }

    #  If requesting by name, and there is more than one result, present a GUI
    if ($LocalizedDisplayName.Count -gt 0 -and $FilteredApps.Count -gt 1) {
        $Selections = @($FilteredApps | Select-Object LocalizedDisplayName, LocalizedDescription, ModelName | Sort LocalizedDisplayName,ModelName | Out-GridView -PassThru | Select -ExpandProperty ModelName)
    } else {
        $Selections = @($FilteredApps | Select -ExpandProperty ModelName)
    }

    #  For each of the found apps, filter by selection, call .Get() to get the XML, add Parent/Child properties, and add to Results
    $FilteredApps | Where {$Selections -contains $_.ModelName} | %{
            $_.Get(); 
            $_ | Add-Member -Name Parent -Value @() -MemberType NoteProperty -PassThru | Add-Member -Name Child -Value @() -MemberType NoteProperty; 
            $Results[$_.ModelName] = $_}
    
    #  Iterate through apps looking for dependencies
    foreach ($Selection in $Selections) {
        $App = $Results[$Selection]
        $SDMPackageXML = [xml]$App.SDMPackageXML

        #  Expand deployment types
        foreach ($DeploymentType in @($SDMPackageXML.AppMgmtDigest.DeploymentType)) {
            foreach ($DeploymentTypeApplicationReference in @($DeploymentType.Dependencies.DeploymentTypeRule.DeploymentTypeExpression.Operands.DeploymentTypeIntentExpression.DeploymentTypeApplicationReference)) {
                #  XML handling is a bit silly and sometimes returns empty objects, so filter them out
                if (-not ([string]::IsNullOrWhiteSpace($DeploymentTypeApplicationReference.AuthoringScopeId))) {
                    #  Recreate the ModelName from the AuthoringScopeId and LogicalName
                    $DepModelName = "$($DeploymentTypeApplicationReference.AuthoringScopeId)/$($DeploymentTypeApplicationReference.LogicalName)"
                    Write-Verbose "'$($Selection)' has dependency '$($DepModelName)'"

                    #  Add a link from parent to child if the link doesn't already exist
                    if (-not ($Results[$Selection].Child -contains $DepModelName)) {
                        $Results[$Selection].Child += $DepModelName
                    }

                    #  Recursively call function to search for dependencies
                    if (-not ($Results.ContainsKey($DepModelName)) -and $Recurse) {
                        $Results = Get-CMDependency -ModelName $DepModelName -ComputerName $ComputerName -Results $Results -Recurse $Recurse
                    }

                    #  Add a link from child to parent if the child was successfully retrieved, and the link doesn't already exist
                    if ($Results.ContainsKey($DepModelName) -and -not ($Results[$DepModelName].Parent -Contains $Selection)) {
                        $Results[$DepModelName].Parent += $Selection
                    }
                }
            }
        }
    }
    return $Results
}

$Dependencies = Get-CMDependency -LocalizedDisplayName '%Some App%','%Some other app%' -Verbose

$Dependencies.Keys
$Dependencies['ScopeId_7823025E-2E5B-4372-983B-0521249B1F02/Application_58eef03a-9c93-490f-8218-1168b1beb20d'].Child
$Dependencies['ScopeId_7823025E-2E5B-4372-983B-0521249B1F02/Application_fc08ae01-3309-4161-8410-7184c6fc61d4'].Parent

Get-CMDependency -LocalizedDisplayName 'Some App 10.3.18153.4' -Verbose


