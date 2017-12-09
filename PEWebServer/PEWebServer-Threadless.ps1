﻿<#
    .Synopsis
        The single threaded version of PEWebServer, which is useful for troubleshooting.
        Creates a Windows PE compatible web server that will invoke PowerShell code based on routes being asked for by the client.
 
    .Description
        For the web server to be visible from outside the system, you must disable the Windows PE firewall with "wpeutil disablefirewall"
 
        Start-PEHTTPServer creates a web server.  The web server functionality is defined by a schema that describes how the client's requests are processed.

        Under the covers, Start-PEHTTPServer uses the System.Net.Sockets.TcpClient .NET class, along with a bunch of code, to partially recreate the System.Net.HttpListener .NET class.
        The HttpListener .NET class is unavailable to be used within Windows PE, which is why TcpClient is used, and HTTP parsing code needed to be written from scratch.
        The custom HTTP parser should support all of the most commonly used features of HTTP (except cookies), but there are certainly HTTP features that will not work.
        For web services outside of Windows PE, it is recommended to use another server that can make use of HttpListener as it will be markedly faster and more featureful.

        When a client performs a GET request on a route that requires a POST, a webpage is automatically served up to allow entering test to post to the route.
    
    .Parameter Verbose
        [Switch]. If the Verbose switch is specified, then the output to the console is extremely verbose.

    .Parameter Port
        [Int]. Specifies a port in the form of a number xx.  For example, port 8000 would make the computer accessible via http://hostname:8000
    
    .Parameter IncludeDefaultSchema
        [Bool]. Specifies whether or not to include the default WebSchema, in addition to the supplied WebSchema
        The definition for the default WebSchema can be viewed in the Update-WebSchema function.  Default routes are:
            /
            /beep
            /browse{Path}
            /download/{Path}
            /favicon.ico
            /jobrun
            /prettyprocess
            /process
            /process/{name}
            /run
            /test
            /upload
            /vnc
            
    .Parameter ShutdownCommand
        [String]. A REGEX string that can be passed to the server via the body of a REST POST request that will cause the web server to shutdown

    .Parameter WebSchema
        @(@{}). WebSchema takes an array of hashetables.  Each element in the array represents a different route requestable by the client.
        For routes, the four values used in the hashtable are Path, Method, Script, and DefaultReply, although DefaultReply is optional.

        Method: Defines the HTTP method that will be used by the client to get to the route. (Get/Post)

        Path: Defines the address in the url supplied by the client after the http://hostname:port/ part of the address.  Path probably support parameters allowed by Nancy.  For example, if you your path is /process/{name}, the value supplied by the requestor for {name} is passed to your script.  You would use the $parameters special variable to access the name property.  In the /process/{name} example, the property would be $parameters.name in your script.
    
        DefaultReply: Specify if the the webserver should handle replying to the HTTP request using its own internal handler, or if the route will reply with its own logic.


        Script: A scriptblock that will be executed when the client requests the path.  
        The scriptblock has a special variable named $Parameters that will contain client parameters.
        In addition to whatever parameters that may be specified by the Path portion of the WebSchema, these $Parameters properties will also exist:
                BodyString: The body of the HTTP request converted to a string
                BodyBytes: The body of the HTTP request as a byte array
                RawUrl: The URL (minus the host name) of the HTTP request
                HttpListenerRequest:  A psobject that as closely matches [System.Net.HttpListenerRequest] as possible
                Stream: The TCP stream that can be written to directly
    
        Here is an example of creating the WebSchema
        $SomeSchema = @(
                @{
                    Path   = '/process'
                    method = 'get'
                    Script = {
                                Get-Process | select name, id, path | ConvertTo-Json
                    }
                },@{
                    Path   = '/process'
                    Method = 'post'
                    Script = { 
                                $processname = $Parameters.BodyString
                                Start-Process $processname
                    }
                },@{
                    Path   = '/process/{name}'
                    Method = 'get'
                    Script = {
                                get-process $parameters.name |convertto-json -depth 1
                    }
                },@{
                    Path   = '/prettyprocess'
                    Method = 'get'
                    Script = {
                                Get-Process | ConvertTo-HTML name, id, path
                    }
                },@{
                    Path   = '/jobrun'
                    Method = 'post'
                    Script = {
                                $Job = Invoke-Command -ScriptBlock ([ScriptBlock]::Create($Parameters.BodyString)) -AsJob -ComputerName localhost
                                $Job | ConvertTo-Json -Depth 1
                    }
                },@{
                    Path   = '/run'
                    Method = 'post'
                    Script = {
                                $out = Invoke-Command -ScriptBlock ([ScriptBlock]::Create($Parameters.BodyString))
                                $out
                    }
                },@{
                    Path   = '/download/{Path}'
                    method = 'get'
                    Script = {
                                Send-File -Path $Parameters.Path -Stream $Parameters.Stream
                    }
                    DefaultReply = $false
                }
            )

 
    .Inputs
        Collection of hashes containing the WebSchema of the web server
 
    .Outputs
        A Web server 
 
    .Example
 
        PS C:\> Start-PEHTTPServer
 
        Creates a web server listening on http://hostname:8000/.  The server will respond with task sequence information when http://hostname:8000 is browsed to.  
        The server will be unreachable from outside of the server it is running until "wpeutil disablefirewall" is run from a command prompt
 
    .Example
 
        PS C:\> Start-PEHTTPServer -Port 8080 -IncludeDefaultSchema $false -WebSchema @(
            Get '/'              { "Welcome to PEWebServer!" }
            Get '/process'       { get-process |select name, id, path |ConvertTo-Json }
            Get '/prettyprocess' { Get-Process |ConvertTo-HTML name, id, path }
        )
        The default web schema is not included, and is replaced by the specied schema.
        It also illustrates how to return text, create a web service that returns JSON, and display HTML visually.
        The above creates three routes that can be accessed by a client (run on the server this was run on because the public switch was not used):
        http://hostname:8080/
        http://hostname:8080/process
        http://hostname:8080/prettyprocess
        
    .Example
 
        PS C:\> Start-PEHTTPServer -ShutdownCommand '^ShutdownTheWebServerNow'
 
        Creates a web server listening on http://hostname:8000/ with the default web schema.
        The web server will shutdown with this command from any computer:
        Invoke-RestMethod -Method Post -Uri 'http://hostname:8080' -Body 'ShutdownTheWebServerNow'
        
    .Example
 
        PS C:\> Start-PEHTTPServer -Port 8080 -Verbose
 
        Creates a web server listening on http://hostname:8080/ with the default web schema.
        All diagnostic information will be output to the console.
 
    .Credits
        Pieces taken from:

        Microsoft PowerShell Polaris
        https://github.com/powershell/polaris

        Tiberriver256 PSWebServer
        https://gist.github.com/Tiberriver256/868226421866ccebd2310f1073dd1a1e
        https://github.com/tiberriver256/PSWebServer/

        Boe Prox TCP Server
        https://learn-powershell.net/2014/02/22/building-a-tcp-server-using-powershell/
        https://gallery.technet.microsoft.com/scriptcenter/TCP-Server-Module-80f781eb
        https://www.powershellgallery.com/packages/PowerShellCookbook/1.3.6

#>


#  Parses the bytes from an HTTP request and returns a psobject that as closely matches [System.Net.HttpListenerRequest] as possible.
#  Bytes are from a TCP connection that are retrieved via:
#  [System.Net.Sockets.TcpListener]->.AcceptTcpClient()->.GetStream()->.Read()
#  Optionally, the TcpClient parameter is used to populate the fields:
#  LocalEndPoint, RemoteEndPoint, UserHostAddress, IsLocal
#  TcpClient is from:
#  [System.Net.Sockets.TcpListener]->.AcceptTcpClient()
function Parse-HTTP {
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        $HTTPBytes, #  Must be a byte array.  [Byte[]]
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [System.Net.IPEndPoint]$LocalEndPoint,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [System.Net.IPEndPoint]$RemoteEndPoint,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [System.Net.Sockets.TcpClient]$TcpClient,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Bool]$OriginalHeader=$True
    )

    [Void][System.Reflection.Assembly]::LoadWithPartialName("System.Web")
    [Void][System.Reflection.Assembly]::LoadWithPartialName("System.Web.HttpUtility")

    if ($TcpClient) {
        $LocalEndPoint = $TcpClient.Client.LocalEndPoint
        $RemoteEndPoint = $TcpClient.Client.RemoteEndPoint
    }

    [Byte[]]$HTTPHeaderBytes = @()
    [Byte[]]$HTTPBodyBytes = @()
    [String]$HTTPHeaderString = $null
    [String]$HTTPBodyString = $null
    [String[]]$HTTPHeaderArray = @()


    $HttpListenerRequest = New-Object psobject -Property @{
            AcceptTypes =            [string[]]@()
            ClientCertificateError = [int]$null
            ContentEncoding =        [System.Text.Encoding]::GetEncoding(1252) # Maybe should be [System.Text.Encoding]::Default ?
            ContentLength64 =        $null #[Long]
            ContentType =            [string]$null
            Cookies =                [System.Collections.Hashtable]@{} #[System.Net.CookieCollection]
            HasEntityBody =          [bool]$false
            Headers =                [System.Collections.Hashtable]@{} #[System.Net.WebHeaderCollection]
            HttpMethod =             [string]$null
            #InputStream =            [System.IO.Stream]
            IsAuthenticated =        [bool]$false
            IsLocal =                [bool]$false
            IsSecureConnection =     [bool]$false
            IsWebSocketRequest =     [bool]$false
            KeepAlive =              [bool]$false
            LocalEndPoint =          [System.Net.IPEndPoint]$LocalEndPoint
            ProtocolVersion =        [version]$null
            QueryString =            [System.Collections.Hashtable]@{} #[System.Collections.Specialized.NameValueCollection]
            RawUrl =                 [string]$null
            RemoteEndPoint =         [System.Net.IPEndPoint]$RemoteEndPoint
            #RequestTraceIdentifier = [guid]
            ServiceName =            [string]$null
            #TransportContext =       [System.Net.TransportContext]
            Url =                    [uri]$null
            UrlReferrer =            [uri]$null
            UserAgent =              [string]$null
            UserHostAddress =        [string]$null
            UserHostName =           [string]$null
            UserLanguages =          [string[]]@()
            BodyBytes =              [Byte[]]@()
            BodyString =             [string]$null
            HeaderString =           [string]$null
            IsValid =                [Bool]$True
            HTTPBytes =              $HTTPBytes
            ContentDisposition =     [System.Collections.Hashtable]@{}
        }


    #  HTTP bodies appear to be seperated from the header by two line/carriage returns
    #  Determine header length if seperated by that amount
    Write-Verbose "Parse-HTTP: Detecting header length from $($HTTPBytes.Count) bytes"
    [Long]$HeaderLength = 0
    $HeaderSearch = Search-Binary -ByteArray $HTTPBytes -Pattern ([Byte[]]@(13,10,13,10)) -First
    if ($HeaderSearch.Count -eq 1) {
        $HeaderLength = $HeaderSearch[0]
    }
    
    Write-Verbose "Parse-HTTP: Copy header bytes"
    [Byte[]]$HTTPHeaderBytes
    if ($HeaderLength -ne 0) {
        $HTTPHeaderBytes = New-Object byte[] $HeaderLength
        [System.Buffer]::BlockCopy($HTTPBytes, 0, $HTTPHeaderBytes, 0, $HeaderLength)
    } else {
        $HTTPHeaderBytes = $HTTPBytes
    }
    Write-Verbose "Parse-HTTP: Header length is $($HTTPHeaderBytes.Count)"

    $HTTPHeaderString = [System.Text.Encoding]::ASCII.GetString($HTTPHeaderBytes)
    $HttpListenerRequest.HeaderString = $HTTPHeaderString.Clone()

    Write-Verbose "Parse-HTTP: Parsing header"
    #  A line return followed by space/tabs are part of the same token
    #  rfc2616 2.2
    $HTTPHeaderString = $HTTPHeaderString -replace '\r\n( |\t)+',''
    
    #  Split header on line returns and remove trailing white space
    $HTTPHeaderArray = @($HTTPHeaderString -split '\r\n' | %{$_.Trim()})

    foreach ($HTTPToken in $HTTPHeaderArray) {
        #  HTTP method tokens seem to take to form of "METHOD URI HTTP_VERSION"
        #  I can't find in the specifications where it specifies the order, so hopefully URI never comes after HTTP_VERSION
        #  But the URI and HTTP_VERSION fields appear to be optional based on several factors
        #  URI doesn't appear to be used on all methods
        #  HTTP_VERSION is optional, unless there are 1.0 compatibility issues
        if ($HTTPToken -match '\A(OPTIONS|GET|HEAD|POST|PUT|DELETE|TRACE|CONNECT)(()()|() (HTTP/[1-9]\.[0-9])| (.*) (HTTP/[0-9]\.[0-9])| (.*)())\Z') {
            #  Using replace in case the $Matches variable gets clobbered during multithreading
            #  Have to use named matches Method/URI/Version instead of $1/$2/$3 because couldn't find a way to access $10 and beyond
            $HttpListenerRequest.HttpMethod = $HTTPToken -replace '\A(?<Method>OPTIONS|GET|HEAD|POST|PUT|DELETE|TRACE|CONNECT)((?<URI>)(?<Version>)|(?<URI>) (?<Version>HTTP/[1-9]\.[0-9])| (?<URI>.*) (?<Version>HTTP/[0-9]\.[0-9])| (?<URI>.*)(?<Version>))\Z','${Method}'
            $RawUrl = $HTTPToken -replace '\A(?<Method>OPTIONS|GET|HEAD|POST|PUT|DELETE|TRACE|CONNECT)((?<URI>)(?<Version>)|(?<URI>) (?<Version>HTTP/[1-9]\.[0-9])| (?<URI>.*) (?<Version>HTTP/[0-9]\.[0-9])| (?<URI>.*)(?<Version>))\Z','${URI}'
            $HttpListenerRequest.RawUrl = [System.Web.HttpUtility]::UrlDecode($RawUrl)
            $HTTPVersion = $HTTPToken -replace '\A(?<Method>OPTIONS|GET|HEAD|POST|PUT|DELETE|TRACE|CONNECT)((?<URI>)(?<Version>)|(?<URI>) (?<Version>HTTP/[1-9]\.[0-9])| (?<URI>.*) (?<Version>HTTP/[0-9]\.[0-9])| (?<URI>.*)(?<Version>))\Z','${Version}'
            if ($HTTPVersion -notlike '') {
                $HttpListenerRequest.ProtocolVersion = [Version]($HTTPVersion -replace 'HTTP/([0-9])\.([0-9])', '$1.$2')
            }

        #  I can't find where it specifies what characters are allowed in the key/name of an HTTP header token
        #  All examples I can find are letters and hyphens only.
        #  Also can't find evidence that a space after the colon is required
        } elseif ($HTTPToken -match '\A([a-z\-]+?): *(.*)\Z') {
            $Name = $HTTPToken -replace '\A([a-z\-]+?): *(.*)\Z','$1'
            $Value = $HTTPToken -replace '\A([a-z\-]+?): *(.*)\Z','$2'
            $HttpListenerRequest.Headers.Add($Name, $Value)
        }
    }
    
    Write-Verbose "Parse-HTTP: Filling out HttpListenerRequest properties"
    try {
        if ($HttpListenerRequest.Headers.ContainsKey('Content-Length')) {
            $HttpListenerRequest.ContentLength64 = [Long]($HttpListenerRequest.Headers['Content-Length'])
        }
        if ($HttpListenerRequest.Headers.ContainsKey('Content-Type')) {
            $HttpListenerRequest.ContentType = [string]($HttpListenerRequest.Headers['Content-Type'])
        }
        if ($HttpListenerRequest.Headers.ContainsKey('User-Agent')) {
            $HttpListenerRequest.UserAgent = [string]($HttpListenerRequest.Headers['User-Agent'])
        }
        if ($HttpListenerRequest.Headers.ContainsKey('Referer')) {
            $HttpListenerRequest.UrlReferrer = [System.Web.HttpUtility]::UrlDecode(($HttpListenerRequest.Headers['Referer']))
        }
        if ($HttpListenerRequest.Headers.ContainsKey('Connection') -and $HttpListenerRequest.Headers['Connection'] -like '*Keep-Alive*') {
            $HttpListenerRequest.KeepAlive = [Bool]$True
        }
        if ($HttpListenerRequest.Headers.ContainsKey('Host')) {
            $HttpListenerRequest.UserHostName = [string]($HttpListenerRequest.Headers['Host'])
            $HttpListenerRequest.Url = "http://$($HttpListenerRequest.UserHostName)$($HttpListenerRequest.RawUrl)"
        }
        if ($HttpListenerRequest.Headers.ContainsKey('Content-Disposition')) {
            [String]$ContentDisposition = $HttpListenerRequest.Headers['Content-Disposition']
            [String[]]$Dispositions = $ContentDisposition -split ';' | %{$_.Trim()}
            [Hashtable]$ContentDispositions = @{}
            foreach ($Disposition in $Dispositions) {
                if ($Disposition.Contains('=') -and $Disposition -match '^(.+?)\s*=\s*"*(.*?)"*$') {
                    $Name  = $Disposition -replace '^(.+?)\s*=\s*"*(.*?)"*$', '$1'
                    $Value = $Disposition -replace '^(.+?)\s*=\s*"*(.*?)"*$', '$2'
                    $ContentDispositions[$Name] = $Value
                } elseif ($Disposition.Contains('=')) {
                    Write-Verbose "Unable to parse content disposition value: $($Disposition)"
                } else {
                    $ContentDispositions[$Disposition] = $Disposition
                }
            }
            $HttpListenerRequest.ContentDisposition = $ContentDispositions
        }
        if ($HttpListenerRequest.LocalEndPoint) {
            $HttpListenerRequest.UserHostAddress = $HttpListenerRequest.LocalEndPoint.ToString()
        }
        if ($HttpListenerRequest.LocalEndPoint -and $HttpListenerRequest.RemoteEndPoint) {
            if ($HttpListenerRequest.LocalEndPoint.Address.IPAddressToString -eq $HttpListenerRequest.RemoteEndPoint.Address.IPAddressToString) {
                $HttpListenerRequest.IsLocal = [bool]$True
            }
        }
    } catch {
        Write-Error "Parse-HTTP: $($Error[0])"
        $HttpListenerRequest.IsValid = $false
    }

    if ($HTTPBytes.LongLength -gt ($HTTPHeaderBytes.LongLength + 4)) {
        Write-Verbose "Parse-HTTP: Copy body bytes"
        $HTTPBodyBytesLength = $HTTPBytes.LongLength - $HTTPHeaderBytes.LongLength - 4
        [Byte[]]$HTTPBodyBytes = New-Object byte[] $HTTPBodyBytesLength
        [System.Buffer]::BlockCopy($HTTPBytes, ($HTTPHeaderBytes.LongLength + 4), $HTTPBodyBytes, 0, $HTTPBodyBytesLength)
        Write-Verbose "Parse-HTTP: Converting body bytes to string"
        $HTTPBodyString = [System.Text.Encoding]::GetEncoding(28591).GetString($HTTPBodyBytes) -replace '[^ -~\r\n]', ''
        Write-Verbose "Parse-HTTP: populating additional properties"
        $HttpListenerRequest.BodyBytes = $HTTPBodyBytes
        $HttpListenerRequest.BodyString = $HTTPBodyString
        $HttpListenerRequest.HasEntityBody = $True

        if ($HttpListenerRequest.HttpMethod -eq 'POST' -and $HttpListenerRequest.ContentType -eq 'application/x-www-form-urlencoded') {
            $HttpListenerRequest.QueryString = [System.Web.HttpUtility]::ParseQueryString(($HttpListenerRequest.BodyString))
        }
    }
    #  If the body size does not match the Content-Length attribute, and it's not the first round of an 'Expect: 100-Continue' request, then throw warning
    if ($HttpListenerRequest.ContentLength64 -ne $null -and $HttpListenerRequest.ContentLength64 -ne $HttpListenerRequest.BodyBytes.LongLength -and -not ($OriginalHeader -and $HttpListenerRequest.Headers.ContainsKey('Expect') -and $HttpListenerRequest.Headers['Expect'] -eq '100-continue')) {
        Write-Warning "Parse-HTTP: Warning: Content-Length is $($HttpListenerRequest.ContentLength64), but BodyBytes length is $($HttpListenerRequest.BodyBytes.LongLength)"
        $HttpListenerRequest.IsValid = $false
    }

    Write-Verbose "Parse-HTTP: Returning HttpListenerRequest"
    return $HttpListenerRequest
}


#  Takes the parsed HTTP data, and perfoms the operations dictated by it.
#  Function writes back to the TCP connection before closing.
#  Bytes are from a TCP connection that are retrieved via:
#  [System.Net.Sockets.TcpListener]->.AcceptTcpClient()->.GetStream()->.Read()
#  TcpClient is from:
#  [System.Net.Sockets.TcpListener]->.AcceptTcpClient()
#  HttpListenerRequest is from the Receive-HTTPData function
function Execute-HTTPRequest {
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [System.Net.Sockets.TcpClient]$TcpClient,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [PSObject]$HttpListenerRequest,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [Object[]]$WebSchema,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        $Stream,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [HashTable]$SharedVariables
    )
    
    $ShutdownCommand = $SharedVariables['ShutdownCommand']
    $Port = $SharedVariables['Port']
    
    [String]$ClientIP = $TCPClient.client.RemoteEndPoint.Address.IPAddressToString
    [String]$ClientPort = $TCPClient.client.RemoteEndPoint.Port
    [String]$Client = "$($ClientIP):$($ClientPort)"

    Write-Verbose "Execute-HTTPRequest: Message received from $($Client)"
    Write-Verbose "Execute-HTTPRequest: Header for $($Client):`n$($HttpListenerRequest.HeaderString)"
    if ($HttpListenerRequest.BodyString.Length -gt 1000) {
        Write-Verbose "Execute-HTTPRequest: Body for $($Client):`n$($HttpListenerRequest.BodyString.Substring(0,1000))"
    } else {
        Write-Verbose "Execute-HTTPRequest: Body for $($Client):`n$($HttpListenerRequest.BodyString)"
    }
    
    #  Checking to see if the posted body was from the New-PostForm.
    If ($HttpListenerRequest.HttpMethod -eq 'POST' -and $HttpListenerRequest.BodyString -match '^(winpepostform=)(.*)$') {
                        Write-Verbose "Execute-HTTPRequest: Changing request body from '$($HttpListenerRequest.BodyString)' to '$($HttpListenerRequest.BodyString -replace '^(winpepostform=)(.*)$', '$2')'"
                        $HttpListenerRequest.BodyString = $HttpListenerRequest.BodyString -replace '^(winpepostform=)(.*)$', '$2'
                        Write-Verbose "Execute-HTTPRequest: Replacing hexadecimal characters as replacement"
                        $HttpListenerRequest.BodyString = [System.Web.HttpUtility]::UrlDecode(($HttpListenerRequest.BodyString))
                    }

    #  Check to see if a shutdown command was sent for the HTTP server
    If (-not ([String]::IsNullOrEmpty($ShutdownCommand)) -and $HttpListenerRequest.BodyString -match $ShutdownCommand) {
        Write-Verbose 'Execute-HTTPRequest: Shutting down...'
        $HTTPResponseBytes = New-HTTPResponseBytes -HTTPBodyString ("Shutting down TCP Server on port $Port" | ConvertTo-Json -Depth 1)
        $SharedVariables['WebServerActive'] = $False
        $Stream.Write($HTTPResponseBytes,0,$HTTPResponseBytes.length)
        return
    } Else {
        Write-Verbose "Execute-HTTPRequest: Creating Response for $($Client)"
        $CurrentRoute = $null
        $AlternateRoute = $null
        #  Determine if a route exists in the schema that matches the request
        $CurrentRoute = $WebSchema | Where-Object {$HttpListenerRequest.RawUrl -match $_.Path -and $_.Method -eq $HttpListenerRequest.HttpMethod} | Select-Object -First 1

        #  If there wasn't a route found, and the method is a get, then see if there is a POST version of the URL.
        #  If there is, provide a page for user to post via a webpage
        if ($CurrentRoute -eq $null -and $HttpListenerRequest.HttpMethod -eq 'GET' -and @($WebSchema | Where-Object {$HttpListenerRequest.RawUrl -match $_.Path}).Count -ne 0) {
            Write-Verbose "Execute-HTTPRequest: Presenting post form for $($Client) $($HttpListenerRequest.RawUrl)"
            $OutputBody = New-PostForm -URI $HttpListenerRequest.RawUrl
            Write-Verbose "Execute-HTTPRequest: Creating HTTP Response for $($Client): $($RunScript)"
            $HTTPResponseBytes = New-HTTPResponseBytes -HTTPBodyString $OutputBody
        } elseif ($CurrentRoute -eq $null) {
            #  If there is no matching route, return a 404 error
            Write-Verbose "Execute-HTTPRequest: Unable to find a route for $($Client) request $($HttpListenerRequest.HttpMethod) on $($HttpListenerRequest.RawUrl)"
            $HTTPResponseBytes = New-HTTPResponseBytes -StatusCode 404 -StatusDescription 'Not Found' -HTTPBodyString '<h1>404 - Page not found</h1>'
        } else {
            Write-Verbose "Execute-HTTPRequest: Matched route for $($Client) request $($HttpListenerRequest.HttpMethod) on $($HttpListenerRequest.RawUrl) as $($CurrentRoute.Path)"
            #  Put matches (for URL variables) and HTTPBodyString/Bytes into parameters variable for script
            $Parameters = @{}
            [Void]($HttpListenerRequest.RawUrl -match $CurrentRoute.Path)
            $Matches.Keys | %{$Parameters[$_]=$Matches[$_]}
            $Parameters['BodyString'] = $HttpListenerRequest.BodyString
            $Parameters['BodyBytes'] = $HttpListenerRequest.BodyBytes
            $Parameters['RawUrl'] = $HttpListenerRequest.RawUrl
            $Parameters['HttpListenerRequest'] = $HttpListenerRequest
            $Parameters['Stream'] = $Stream
            Write-Verbose "Execute-HTTPRequest: Collected parameters for $($Client): `n$($Parameters | Out-String)"

            Write-Verbose "Execute-HTTPRequest: Running script for $($Client): $($CurrentRoute.Script | Out-String)"
            $OutputBody = Invoke-Command -ScriptBlock $CurrentRoute.Script -ArgumentList $Parameters

            #  Create a generic reply if the route didn't handle it
            if ($CurrentRoute.DefaultReply) {
                if ($OutputBody -eq $null) {
                    $OutputBody = ''
                }
                if ($OutputBody.GetType().FullName -ne 'System.String') {
                    try {
                        $OutputBody = $OutputBody | Out-String
                    } catch {
                        Write-Verbose "Execute-HTTPRequest: Failed to convert OutputBody of type [$($OutputBody.GetType().FullName)] to [String] for $($Client)"
                        Write-Verbose "Execute-HTTPRequest: Will Format-List instead for $($Client)"
                        $OutputBody = $OutputBody | fl *
                    }
                }
                Write-Verbose "Execute-HTTPRequest: Creating HTTP Response for $($Client): `n$($OutputBody)"
                $HTTPResponseBytes = New-HTTPResponseBytes -HTTPBodyString $OutputBody
            }
        }
    }

    if ($CurrentRoute -eq $null -or $CurrentRoute.DefaultReply) {
        Write-Verbose "Execute-HTTPRequest: Echoing $($HTTPResponseBytes.count) bytes to $($Client)"
        $Stream.Write($HTTPResponseBytes,0,$HTTPResponseBytes.length)
    }
}


#  Reads data from the TCP stream, and prepares it for the Parse-HTTP function.
#  The HttpListenerRequest object returned by Parse-HTTP is returned to the caller
#  Stream bytes are from a TCP connection that are retrieved via:
#  [System.Net.Sockets.TcpListener]->.AcceptTcpClient()->.GetStream()
#  as
#  [System.Net.Sockets.NetworkStream]->.Read()
#  TcpClient is from:
#  [System.Net.Sockets.TcpListener]->.AcceptTcpClient()
function Receive-HTTPData {
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [System.Net.Sockets.TcpClient]$TcpClient,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [System.Net.Sockets.NetworkStream]$Stream,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [HashTable]$SharedVariables
    )

    [Int]$BufferSize = 65536
    [Byte[]]$Bytes = New-Object byte[] $BufferSize
    $BytesList = New-Object System.Collections.ArrayList
    [Byte[]]$HTTPBytes = @()
    [Bool]$OriginalHeader = $True
    [PSObject]$HttpListenerRequest = New-Object psobject -Property @{IsValid = [Bool]$False; HTTPBytes = [Byte[]]@()}
    
    [String]$ClientIP = $TCPClient.client.RemoteEndPoint.Address.IPAddressToString
    [String]$ClientPort = $TCPClient.client.RemoteEndPoint.Port
    [String]$Client = "$($ClientIP):$($ClientPort)"
    Write-Verbose "Receive-HTTPData: Connection status: $($TCPClient.Connected) from $($Client)"
    
    [Bool]$OriginalHeader = $True
    $StopWatch = New-Object -TypeName System.Diagnostics.Stopwatch
    $StopWatch.Start()
    While ($SharedVariables['WebServerActive'] -and ($TCPClient.Connected -or $Stream.DataAvailable)) {
        #Write-Verbose "Receive-HTTPData: Data availability: $($Stream.DataAvailable) from $($Client)"
        #  Retrieve data from socket buffer
        If ($Stream.DataAvailable) {
            Do {
                $Bytes.Clear()
                Write-Verbose "Receive-HTTPData: $($TCPClient.Available) Bytes available from $($Client)"
                $BytesReceived = $Stream.Read($Bytes, 0, $Bytes.Length)
                If ($BytesReceived -gt 0) {
                    Write-Verbose "Receive-HTTPData: $bytesReceived Bytes received from $($Client)"
                    if ($BytesReceived -eq $BufferSize) {
                        $BytesList.AddRange($Bytes)
                    } else {
                        $BytesList.AddRange($Bytes[0..($BytesReceived - 1)])
                    }
                }
                if ($TCPClient.Connected -and -not ($Stream.DataAvailable)) {
                    Start-Sleep -Milliseconds 250
                }
            } While ($Stream.DataAvailable)

            #  Copy arraylist to normal byte array
            $HTTPBytes = New-Object byte[] ($BytesList.Count)
            $BytesList.CopyTo($HTTPBytes)

            #  Parse HTTP header/body into object that is similar to [System.Net.HttpListenerRequest]
            Write-Verbose "Receive-HTTPData: Parsing $($HTTPBytes.Count) bytes received from $($Client)"
            $HttpListenerRequest = Parse-HTTP -HTTPBytes $HTTPBytes -TcpClient $TCPClient

            if ($OriginalHeader -and $HttpListenerRequest.Headers.ContainsKey('Expect') -and $HttpListenerRequest.Headers['Expect'] -eq '100-continue') {
                Write-Verbose "Receive-HTTPData: 'Expect: 100-continue' received from $($Client)"
                $OriginalHeader = $false
                [Byte[]]$HTTPResponseBytes = New-HTTPResponseBytes -StatusCode 100 -StatusDescription '(Continue)' -Headers @{}
                Write-Verbose "Receive-HTTPData: Replying with $($HTTPResponseBytes.count) bytes to $($Client) to request additional payload"
                $Stream.Write($HTTPResponseBytes,0,$HTTPResponseBytes.length)
            } elseif ($HttpListenerRequest.IsValid -and -not ($Stream.DataAvailable)) {
                Write-Verbose "Receive-HTTPData: Successfully parsed $($HTTPBytes.count) bytes from $($Client)"
                return $HttpListenerRequest
            }

            #  Reset timer
            $StopWatch.Restart()
        }

        
        Start-Sleep -Milliseconds 100
        if (-not ($Stream.DataAvailable)) {
            #  Clear out a hung connection
            if ($BytesList.Count -eq 0 -and $StopWatch.ElapsedMilliseconds -gt 500) {
                Write-Warning "Receive-HTTPData: Closing Connection with no data from $($Client)"
                return $HttpListenerRequest
            } elseif ($StopWatch.ElapsedMilliseconds -gt 2000) {
                Write-Warning "Receive-HTTPData: Closing expired connection from $($Client)"
                return $HttpListenerRequest
            } elseif (-not ($SharedVariables['WebServerActive'])) {
                Write-Warning "Receive-HTTPData: Server shutting down. Closing connection from $($Client)"
                return $HttpListenerRequest
            }
        }
    }
    Write-Warning "Receive-HTTPData: Connection closed unexpectedly from $($Client)"
    return $HttpListenerRequest
}


#  Create an HTTP response, and convert to bytes
#  The parameters should coincide with the properties of [System.Net.HttpListenerRequest]
Function New-HTTPResponseBytes {
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Byte[]]$HTTPBodyBytes = @(),
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String]$HTTPBodyString = $null,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String]$HTTPServer = 'WinPE-HTTPAPI/1.0',
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [System.Text.Encoding]$ContentEncoding = [System.Text.Encoding]::GetEncoding(1252),   # Not to be confused with the Content-Encoding HTTP header, which is about compression
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String]$ContentType = $null,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Long]$ContentLength64 = $null,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        $Cookies = @{},
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        $Headers = @{Connection = 'close'},
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Bool]$KeepAlive = $False,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Version]$ProtocolVersion = '1.1',
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String]$RedirectLocation = $null,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Bool]$SendChunked = $False,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Int]$StatusCode = 200,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String]$StatusDescription = 'OK',
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String]$Date = (Get-Date -Format r)
    )

    #  Convert string body to bytes, or use already converted bytes
    if ($HTTPBodyString -ne $null -and $HTTPBodyString.Length -gt $HTTPBodyBytes.Count) {
        Write-Verbose "New-HTTPResponseBytes: Converting string HTTPBodyString of length $($HTTPBodyString.Length) to byte array"
        $HTTPBodyBytes = [System.Text.Encoding]::ASCII.GetBytes($HTTPBodyString)
    }

    if ($ContentLength64 -eq 0) {
        [Long]$ContentLength64 = $HTTPBodyBytes.LongLength
    }
    Write-Verbose "New-HTTPResponseBytes: HTTPBodyBytes is length $($ContentLength64)"

    #  Create the HTTP headers with default values, and then add additional header values
    $HTTPHeaderString = "HTTP/$($ProtocolVersion.ToString()) $($StatusCode) $($StatusDescription)`r`nContent-Length: $($ContentLength64)`r`nServer: $($HTTPServer)`r`nDate: $($Date)`r`n"
    Write-Verbose "New-HTTPResponseBytes: HTTPHeaderString is length $($HTTPHeaderString.Length)"
    if (-not ([String]::IsNullOrWhiteSpace($ContentType))) {
        $HTTPHeaderString += "Content-Type: $($ContentType)`r`n"
    }
    Write-Verbose "New-HTTPResponseBytes: Adding $($Headers.Count) headers"
    foreach ($Name in $Headers.Keys) {
        $HTTPHeaderString += "$($Name): $($Headers[$Name])`r`n"
    }
    $HTTPHeaderString += "`r`n"
    Write-Verbose "New-HTTPResponseBytes: Final HTTPHeaderString length is $($HTTPHeaderString.Length)"
    Write-Verbose "New-HTTPResponseBytes: Final HTTPHeaderString: `n$($HTTPHeaderString)"

    #  Convert header to byte array, and then concatenate the body
    [Byte[]]$HTTPResponseBytes = [System.Text.Encoding]::ASCII.GetBytes($HTTPHeaderString)
    Write-Verbose "New-HTTPResponseBytes: HTTPResponseBytes header length is $($HTTPResponseBytes.Length)"
    $HTTPResponseBytes += $HTTPBodyBytes
    Write-Verbose "New-HTTPResponseBytes: Final HTTPResponseBytes length is $($HTTPResponseBytes.Length)"

    return $HTTPResponseBytes
}


#  When a POST URL is accessed with a GET, this function generates an HTML form to return to the user
#  to allow them to post
function New-PostForm {
    param(
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [String]$URI
    )
    $HTMLPostForm = @'
        <!DOCTYPE html>
        <html>
        <body>
        <p>This URL requires POST instead of GET.  You may try inputting data here to attempt to post.</p>
        <form action="/PreviousGETLocation" id="usrform" method="post">
        <textarea rows="20" cols="100" name="winpepostform" form="usrform"></textarea>
        <input type="submit">
        </form>
        </body>
        </html>
'@

    $HTMLPostForm = $HTMLPostForm -replace '/PreviousGETLocation',$URI

    return $HTMLPostForm
}


#  Search a byte array for a byte pattern and return all (or first) results
function Search-Binary {
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        $ByteArray,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [Byte[]]$Pattern,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Switch]$First
    )
    
    #  Original method function originally by Tommaso Belluzzo
    #  https://stackoverflow.com/questions/16252518/boyer-moore-horspool-algorithm-for-all-matches-find-byte-array-inside-byte-arra
    $MethodDefinition = @'

        public static System.Collections.Generic.List<Int64> IndexesOf(Byte[] ByteArray, Byte[] pattern, bool first = false)
        {
            if (ByteArray == null)
                throw new ArgumentNullException("ByteArray");

            if (pattern == null)
                throw new ArgumentNullException("pattern");

            Int64 ByteArrayLength = ByteArray.LongLength;
            Int64 patternLength = pattern.LongLength;
            Int64 searchLength = ByteArrayLength - patternLength;

            if ((ByteArrayLength == 0) || (patternLength == 0) || (patternLength > ByteArrayLength))
                return (new System.Collections.Generic.List<Int64>());

            Int64[] badCharacters = new Int64[256];

            for (Int64 i = 0; i < 256; ++i)
                badCharacters[i] = patternLength;

            Int64 lastPatternByte = patternLength - 1;

            for (Int64 i = 0; i < lastPatternByte; ++i)
                badCharacters[pattern[i]] = lastPatternByte - i;

            // Beginning

            Int64 index = 0;
            System.Collections.Generic.List<Int64> indexes = new System.Collections.Generic.List<Int64>();

            while (index <= searchLength)
            {
                for (Int64 i = lastPatternByte; ByteArray[(index + i)] == pattern[i]; --i)
                {
                    if (i == 0)
                    {
                        indexes.Add(index);
                        if (first)
                            return indexes;
                        break;
                    }
                }

                index += badCharacters[ByteArray[(index + lastPatternByte)]];
            }

            return indexes;
        }
'@

    if (-not ([System.Management.Automation.PSTypeName]'Random.Search').Type) {
        Add-Type -MemberDefinition $MethodDefinition -Name 'Search' -Namespace 'Random' | Out-Null
    }
    return [Random.Search]::IndexesOf($ByteArray, $Pattern, $First)
}


#  Parse data from HTML forms sent as Multiparts
#  This is used when submitting files
function Parse-MultipartFormData {
    param(
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [String]$HttpMethod,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [PSObject]$HttpListenerRequest
    )

    #  Return object
    [System.Collections.ArrayList]$MultiParts = New-Object System.Collections.ArrayList
    
    if ($HttpListenerRequest.Headers.ContainsKey('Content-Type')) {
        #  Splitting to Content-Type header to verify it is multipart
        [String[]]$ContentType = @($HttpListenerRequest.Headers['Content-Type'] -split ';' | %{$_.Trim()})
        if ($ContentType.Contains('multipart/form-data')) {
            #  Verify there is a boundary value in the Content-Type header
            [String]$Boundary = $ContentType | Where {$_ -like 'boundary=*' -or $_ -like 'boundary =*'} | %{$_ -replace '^(.+?)\s*=\s*"*(.*?)"*$', '$2'}
            if (-not ([String]::IsNullOrEmpty($Boundary))) {
                #  For some reason the boundary specified in the headers is preceeded by two hyphens
                $Boundary = '--' + $Boundary
                Write-Verbose "Parse-MultipartFormData: Boundary is:`n$($Boundary)"

                
                #  A pattern of bytes to find
                [Byte[]]$BB = $HttpListenerRequest.BodyBytes
                [Int]$BBL = $BB.Count
                #  A pattern bytes to find
                [Byte[]]$BoB = [System.Text.Encoding]::ASCII.GetBytes($Boundary)
                [Int]$BoBL = $BoB.Count

                $Locations = Search-Binary -ByteArray $BB -Pattern $BoB

                <#
                #  A pattern of bytes to find
                [Byte[]]$BB = $HttpListenerRequest.BodyBytes
                #  Byte locations of all places pattern occurs in the array
                [Int[]]$Locations = @()
                
                #  Convert data to hex string to search for boundary codes using -split
                [String]$BBS = [System.BitConverter]::ToString(($HttpListenerRequest.BodyBytes)) -replace '-',''
                [String]$BoBS = [System.BitConverter]::ToString(($BoB)) -replace '-',''
                #  Length of byte pattern as a hex string
                [Int]$BoBSL = $BoBS.Length
                #  Split string into array of strings on the byte pattern
                [String[]]$BBSArray = $BBS -split $BoBS
                #  Iterate through array of strings to see their sizes to calculate where the byte pattern occured
                [Int]$ByteCount = 0
                foreach ($BBSEntry in $BBSArray) {
                    $ByteCount = $ByteCount + $BBSEntry.Length
                    #  Divide byte count by 2 because it is 2 string characters per byte
                    $Locations += $ByteCount / 2
                    $ByteCount = $ByteCount + $BoBSL
                }

                Remove-Variable BBS
                #>
                
                <#
                #  Search through byte array for boundary value
                #  This method appears to be ~10x slower than converting to a hex string to search
                #  Pattern length
                [Int]$BoBL = $BoB.Count
                #  Length of byte array
                [Int]$BBL = $BB.Count
                #  Byte array length, minus the length of the pattern.
                #  Used to keep searching from going to the end of the array
                [Int]$BBDiff = $BBL - $BoBL
                for ([Int]$i = 0; $i -lt $BBDiff; $i++) {
                    $Found = $True
                    for ([Int]$k = 0; $k -lt $BoBL; $k++) {
                        if ($BoB[$k] -ne $BB[$i + $k]) {
                            $Found = $false
                            break;
                        }
                    }
                    if ($Found) {
                        $Locations += $i
                        $i = $i + $BoBL
                    }
                }
                #>

                Write-Verbose "Parse-MultipartFormData: Found $($Locations.Count) boundary matches in $($HttpListenerRequest.BodyBytes.Count) bytes at: $(($Locations | Out-String) -replace "`r`n", ', ')"
                
                $Segments = New-Object System.Collections.ArrayList
                #  Copy identified segments out of byte array to new arraylist
                for ([Int]$i = 0; $i -lt ($Locations.Count - 1); $i++) {
                    $Loc = $Locations[$i]
                    $LocNext = $Locations[$i + 1]
                    Write-Verbose "Parse-MultipartFormData: Segment $Loc to $LocNext bounded by $($BB[$Loc - 2]),$($BB[$Loc - 1]) and $($BB[$Loc + $BoBL]),$($BB[$Loc + $BoBL + 1])"
                    #  Validate entries with the following criteria
                    #  If the segment is at least the length of the boundary + 4 bytes
                    #  AND    first entry followed by line return
                    #      OR first entry followed by two hyphens and a line return
                    #      OR line return followed by entry followed by line return
                    #      OR line return followed by entry followed by two hyphens and a line return
                    if (($BBL -gt ($Loc + $BoBL + 4) -and
                        (($Loc -eq 0 -and $BB[$Loc + $BoBL] -eq 13 -and $BB[$Loc + $BoBL + 1] -eq 10) -or
                         ($BB[$Loc - 2] -eq 13 -and $BB[$Loc - 1] -eq 10 -and $BB[$Loc + $BoBL] -eq 13 -and $BB[$Loc + $BoBL + 1] -eq 10) -or
                         ($BB[$Loc - 2] -eq 13 -and $BB[$Loc - 1] -eq 10 -and $BB[$Loc + $BoBL] -eq 45 -and $BB[$Loc + $BoBL + 1] -eq 45 -and $BB[$Loc + $BoBL + 2] -eq 13 -and $BB[$Loc + $BoBL + 3] -eq 10)))) {
                        
                        Write-Verbose "Parse-MultipartFormData: Adding byte segment from $($Loc + $BobL + 2) to $($LocNext - 2)"
                        $TempBytesLength = ($LocNext - 2) - ($Loc + $BoBL + 2)
                        [Byte[]]$TempBytes = New-Object byte[] $TempBytesLength
                        [System.Buffer]::BlockCopy($BB, ($Loc + $BobL + 2), $TempBytes, 0, $TempBytesLength)
                        [Void]$Segments.Add($TempBytes)
                    }
                }

                Write-Verbose "Parse-MultipartFormData: There were $($Segments.Count) segments found"
                if ($Segments.Count -ne 0) {
                    foreach ($Segment in $Segments) {
                        [Void]$MultiParts.Add((Parse-HTTP -HTTPBytes $Segment))
                    }
                }
            }
        }
    }

    return $MultiParts
}


#  On GET request, returns a form to submit files for upload
#  On POST requests, download files and save them
function New-Upload {
    param(
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [String]$RawURL,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [String]$HttpMethod,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [PSObject]$HttpListenerRequest,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String]$Path = ((Get-Location).Path)
    )

    if ($HttpMethod -eq 'GET') {
        $HTMLPostForm = @'
            <!DOCTYPE html><html><body><p>Please select a file to upload.</p>
            <form action="/PreviousGETLocation" id="uploadform" method="post" enctype="multipart/form-data">
            <input type="file" name="myfile1">
            <input type="file" name="myfile2">
            <input type="file" name="myfile3">
            <input type="file" name="myfile4">
            <input type="submit">
            </form></body></html>
'@

        $HTMLPostForm = $HTMLPostForm -replace '/PreviousGETLocation',$RawURL

        Write-Verbose "New-Upload: Returning HTMLPostForm of size $($HTMLPostForm)"

        return $HTMLPostForm
    }

    [System.Collections.ArrayList]$MultiParts = Parse-MultipartFormData -HttpMethod $HttpMethod -HttpListenerRequest $HttpListenerRequest
    [String[]]$Files = @()

    if ($MultiParts.Count -ne 0) {
        Write-Verbose "New-Upload: $($MultiParts.Count) form entries found"
        foreach ($MultiPart in $MultiParts) {
            if ($MultiPart.ContentDisposition.ContainsKey('filename') -and -not ([String]::IsNullOrEmpty($MultiPart.ContentDisposition['filename']))) {
                $Filename = $MultiPart.ContentDisposition['filename']
            } elseif ($MultiPart.BodyBytes.Count -gt 0) {
                Write-Warning "New-Upload: Multipart form entry is missing valid file name.  Generating random name"
                $Filename = "$(Get-Date -Format 'yyyyMMddHHmmss')-$([Guid]::NewGuid())"
            } else {
                Write-Warning "New-Upload: Multipart form entry is missing valid file name and data"
                continue
            }
            try {
                Write-Verbose "New-Upload: Saving '$($Filename)' with $($MultiPart.BodyBytes.Count) bytes"
                [System.IO.File]::WriteAllBytes("$(Join-Path -Path $Path -ChildPath $Filename)", ($MultiPart.BodyBytes))
                $Files += "$($Filename), $($MultiPart.BodyBytes.Count)"
            } catch {
                Write-Error "New-Upload: Failed to write '$($Filename)' with $($MultiPart.BodyBytes.Count) bytes"
            }
        }
    }

    Remove-Variable MultiParts
    [System.GC]::Collect()

    if ($Files.Count -gt 0) {
        return "$($Files.Count) written to disk. $($Files -join '; ')"
    } else {
        return 'No files were uploaded'
    }
}


#  Generates navigatable HTML directory structure
#  Should support all PSDrive types
#  Path is everything after "/browse/", including the slash
#  RawUrl is the full URL without the hostname
#  This was the easiest way to support a lack of trailing slashes
function Browse-HTMLFileSystem {
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String]$Path,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String]$RawUrl
    )

    #  Look for an empty path, or a missing trailing slash to determine if the HTML A Link should be relative or not to the current path
    if ([String]::IsNullOrEmpty($Path) -or $Path -match '[^/]$') {
        $u = "$($RawUrl)/"
    } else {
        $u = './'
    }

    #  Prefered order of columsn to display
    $DisplayOrder = @{
                PSDrive = @('Name','Used','Free','Root','Description')
                Alias = @('DisplayName','Name','ResolvedCommand','Version','Source')
                Certificate = @('PSChildName','FriendlyName','NotBefore','NotAfter','Issuer','Subject','HasPrivateKey')
                FileSystem = @('Name','Length','LastWriteTime','Mode')
                Environment = @('Name', 'Value')
                Function = @('Name','Version','Source')
                Registry = @('PSChildName','Value','Type','ValueCount')
                Variable = @('Name','Value','Description','Options')
                WSMan = @('PSChildName','Value','Type')
            }
    
    #  Top of the HTML
    [String]$HTMLOut = '<!DOCTYPE html><html><body>'

    #  Break up the URL path into a valid local path
    if ([String]::IsNullOrEmpty($Path) -or $Path -eq '/') {
        $Locations = @(Get-PSDrive)
        $Provider = "PSDrive"
    } else {
        $HTMLOut += "<p><a href=`"../`">Up level</a></p>`r`n"
        $Drive = $Path -replace '^/(.+?)/.*$', '$1'
        $FolderPath = $Path -replace '^/.+?(/.*)$','$1' -replace '/','\'
        $LocalPath = "$($Drive):$($FolderPath)"
        Write-Verbose "Browse-HTMLFileSystem: Path is $($LocalPath)"
        if (Test-Path -Path $LocalPath -PathType Container) {
            $Provider = (Get-PSDrive $Drive).Provider.Name
            $Locations = @(Get-ChildItem $LocalPath -Force)
        } else {
            return '<!DOCTYPE html><html><body>Invalid path</body></html>'
        }
    }
    
    #  Generate a list of table columns to display to the end user
    if ($Locations.Count -ne 0) {
        $Properties = @($Locations | Get-Member | Where {$_.MemberType -like "*Property"} | Select -Expand Name)
    } else {
        $Properties = @()
    }
    if ($DisplayOrder.ContainsKey($Provider)) {
        $CurrentProperties = @($DisplayOrder[$Provider] | Where {$Properties -contains $_})
    } else {
        $CurrentProperties = $Properties
    }
    if ($Provider -eq 'Registry') {
        $CurrentProperties = @('PSChildName','ValueCount','Type','Value')
    }
    
    #  Header at top to show a back link, and the current path
    $HTMLOut += "<p>Provider: $($Provider)</p>`r`n"
    $HTMLOut += "<p>Path: $($LocalPath)</p>`r`n"
    
    #  Print table headers
    $HTMLOut += '<table border="1"><tr>'
    $HTMLOut += "<th>$($CurrentProperties[0])</th>"
    $First = $CurrentProperties[0]
    #  All properties but the first one
    if ($CurrentProperties.Count -gt 1) {
        $CurrentProperties = @($CurrentProperties[1..($CurrentProperties.Count -1)])
        foreach ($CurrentProperty in $CurrentProperties) {
            $HTMLOut += "<th>$($CurrentProperty)</th>"
        }
    } else {
        $CurrentProperties = @()
    }
    $HTMLOut += "</tr>`r`n"

    [String]$PropString = ''

    #  Print out each file/folder/container/key with desired information
    foreach ($Loc in $Locations) {
        if ($Provider -eq 'PSDrive' -or $Loc.PSIsContainer) {
            #  If a folder/container, include a link to show its contents
            $HTMLOut += "<tr><td><a href=`"$($u)$($Loc.($First))/`">$($Loc.($First))</a></td>"
        } elseif ($Provider -eq 'FileSystem') {
            #  If a file, put a download link
            $DownloadURL = "/download/$($Drive)$($FolderPath)$($Loc.($First))" -replace '\\', '/'
            $HTMLOut += "<tr><td><a href=`"$($DownloadURL)`">$($Loc.($First))</a></td>"
        } else {
            $HTMLOut += "<tr><td>$($Loc.$($First))</td>"
        }
        #  Include the other desired item properties
        if ($CurrentProperties.Count -gt 0) {
            foreach ($CurrentProperty in $CurrentProperties) {
                if ($Provider -eq 'Variable') {
                    #  Variable values sometimes are Hashtables, or other things which are best displayed with out-string
                    if ($Loc."$CurrentProperty" -eq $null) {
                        $PropString = ""
                    } else {
                        $PropString = "$($Loc."$CurrentProperty" | Out-String)"
                    }
                } else {
                    $PropString = "$($Loc."$CurrentProperty")"
                }
                #  Escape control HTML characters
                $PropString = [System.Web.HttpUtility]::HtmlEncode(($PropString)) -replace '\n', '<br>' -replace '\r', ''
                $HTMLOut += "<td>" + $PropString + "</td>"
            }
        }
        $HTMLOut += "</tr>`r`n"
    }
    #  Registry values are described as properties of the keys/containers
    #  To get them to display in a reasonable manner requires special handling
    if ($Provider -eq 'Registry') {
        $Properties = (Get-Item -Path $LocalPath).Property
        $Values = Get-ItemProperty -Path $LocalPath
        foreach ($Prop in $Properties) {
            $HTMLOut += "<tr><td>"
            $HTMLOut += [System.Web.HttpUtility]::HtmlEncode(($Prop)) -replace '\n', '<br>' -replace '\r', ''
            $HTMLOut += '</td><td></td><td>'
            $HTMLOut += [System.Web.HttpUtility]::HtmlEncode(($Values."$Prop".GetType().Name)) -replace '\n', '<br>' -replace '\r', ''
            $HTMLOut += '</td><td>'
            $HTMLOut += [System.Web.HttpUtility]::HtmlEncode(($Values."$Prop" | Out-String)) -replace '\n', '<br>' -replace '\r', ''
            $HTMLOut += '</td></tr>'
        }
    }

    #  Close out table and page
    $HTMLOut += '</table></body></html>'


    return $HTMLOut
}


#  Takes a file path, and writes the data back on the TCP stream
#  Path is everything after "/download/", not including the slash
#  Stream bytes are from a TCP connection that are retrieved via:
#  [System.Net.Sockets.TcpListener]->.AcceptTcpClient()->.GetStream()
#  as
#  [System.Net.Sockets.NetworkStream]->.Read()
#  HeaderOnly is for returning a reply to an HTTP HEAD request, which does not include file contents
#  HeaderOnly is not yet implemented
function Send-File {
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String]$Path,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [System.Net.Sockets.NetworkStream]$Stream,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Bool]$HeaderOnly = $false
    )

    
    $Drive = $Path -replace '^(.+?)/.*$', '$1'
    $FolderPath = $Path -replace '^.+?(/.*)$','$1' -replace '/','\'
    $LocalPath = "$($Drive):$($FolderPath)"
    Write-Verbose "Send-File: Path is $($LocalPath)"

    #  If there is no file, return a 404 error
    if ([String]::IsNullOrEmpty($Path) -or -not (Test-Path -Path $LocalPath -PathType Leaf) -or (Get-Item -Path $LocalPath).PSProvider.Name -ne 'FileSystem') {
        Write-Verbose "Send-File: Unable to find find file"
        $HTTPResponseBytes = New-HTTPResponseBytes -StatusCode 404 -StatusDescription 'Not Found' -HTTPBodyString '<h1>404 - File not found</h1>'
        $Stream.Write($HTTPResponseBytes,0,$HTTPResponseBytes.length)
        return
    }
    
    [String]$FileName = (Get-Item -Path $LocalPath).Name
    [String]$LastModified = Get-Date -Date ((Get-Item $LocalPath).LastWriteTime) -Format r
    
    try {
        $FileStream = New-Object -TypeName System.IO.FileStream -ArgumentList ((Resolve-Path -Path $LocalPath), 'Open', 'Read', 'ReadWrite')
        if ($FileStream.CanRead) {
            $Headers = @{
                'Content-Disposition' = "attachment; filename=$($FileName)"
                'Content-Transfer-Encoding' = 'binary'
                'Content-Description' = 'File Transfer'
                'Cache-Control' = 'no-cache, no-store, must-revalidate'
                'Pragma' = 'no-cache'
                'Expires' = '0'
                'Last-Modified' = $LastModified
            }
            [Long]$FileLength = $FileStream.Length
            Write-Verbose "Send-File: Sending file of size: $($FileLength) bytes"
            $HTTPResponseBytes = New-HTTPResponseBytes -Headers $Headers -ContentLength64 $FileLength
            $Stream.Write($HTTPResponseBytes,0,$HTTPResponseBytes.length)
            Write-Verbose "Send-File: Copying file stream"
            $FileStream.CopyTo($Stream)
            $FileStream.Flush()
            $FileStream.Dispose()

            Remove-Variable HTTPResponseBytes
            [System.GC]::Collect()

            return
        } else {
            Write-Verbose "Send-File: Unable to read file"
        }
    } catch {
        Write-Verbose "Send-File: Unable to open file for reading"
    }
    $HTTPResponseBytes = New-HTTPResponseBytes -StatusCode 500 -StatusDescription 'Server Error' -HTTPBodyString '<h1>500 - Unable to open file for reading</h1>'
    $Stream.Write($HTTPResponseBytes,0,$HTTPResponseBytes.length)
    $FileStream.Flush()
    $FileStream.Dispose()
}


#  Sends a simple/small favicon.ico when one is requested, specifying to cache it
#  The .ico is embedded in the script and there are no external dependencies
function Send-Favicon {
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True,Mandatory=$True)]
        [System.Net.Sockets.NetworkStream]$Stream
    )

    #  Base64 encoded favicon
    #  Orange
    $i='AAABAAEAEBACAAEAAQBWAAAAFgAAAIlQTkcNChoKAAAADUlIRFIAAAAQAAAAEAgGAAAAH/P/YQAAAB1JREFUOI1j/J/G8J+BAsBEieZRA0YNGDVgMBkAAPYQAoQr19wQAAAAAElFTkSuQmCC'
    $Favicon = [System.Convert]::FromBase64String($i)
    
    $Headers = @{
        'Content-Type' = 'image/x-icon'
        'Cache-Control' = 'max-age=31556926'
    }
    [Long]$FileLength = $FileStream.Length
    $HTTPResponseBytes = New-HTTPResponseBytes -Headers $Headers -HTTPBodyBytes $Favicon
    Write-Verbose "Send-Favicon: Sending response of size: $($HTTPResponseBytes.Count) bytes"
    $Stream.Write($HTTPResponseBytes,0,$HTTPResponseBytes.length)
}


#  Merge/replace the default web schema with the user provided web schema
#  User provided schema takes precedence.  
function Update-WebSchema {
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Object[]]$WebSchema = @(),
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Bool]$IncludeDefaultSchema = $True
    )

    $DefaultSchema = @(
            @{
                Path   = '/'
                Method = 'get'
                Script = {
                            Get-SystemInformation | ConvertTo-Json
                }
            },@{
                Path   = '/beep'
                Method = 'post'
                Script = {
                            [Void](Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -Command & {[console]::beep($($Parameters.BodyString))}")
                }
            },@{
                Path   = '/browse{Path}'
                method = 'get'
                Script = {
                            Browse-HTMLFileSystem -Path $Parameters.Path -RawUrl $Parameters.RawUrl
                }
            },@{
                Path   = '/download/{Path}'
                method = 'get'
                Script = {
                            Send-File -Path $Parameters.Path -Stream $Parameters.Stream
                }
                DefaultReply = $false
            },@{
                Path   = '/favicon.ico'
                method = 'get'
                Script = {
                            Send-Favicon -Stream $Parameters.Stream
                }
                DefaultReply = $false
            },@{
                Path   = '/jobrun'
                Method = 'post'
                Script = {
                            $Job = Invoke-Command -ScriptBlock ([ScriptBlock]::Create($Parameters.BodyString)) -AsJob -ComputerName localhost
                            $Job | ConvertTo-Json -Depth 1
                }
            },@{
                Path   = '/prettyprocess'
                Method = 'get'
                Script = {
                            Get-Process | ConvertTo-HTML name, id, path
                }
            },@{
                Path   = '/process'
                method = 'get'
                Script = {
                            Get-Process | select name, id, path | ConvertTo-Json
                }
            },@{
                Path   = '/process'
                Method = 'post'
                Script = { 
                            $processname = $Parameters.BodyString
                            Start-Process $processname
                }
            },@{
                Path   = '/process/{name}'
                Method = 'get'
                Script = {
                            get-process $parameters.name |convertto-json -depth 1
                }
            },@{
                Path   = '/run'
                Method = 'post'
                Script = {
                            $out = Invoke-Command -ScriptBlock ([ScriptBlock]::Create($Parameters.BodyString))
                            $out
                }
            },@{
                Path   = '/test'
                Method = 'get'
                Script = {
                            Invoke-Command -ScriptBlock {Test-Function}
                }
            },@{
                Path   = '/upload'
                Method = 'get'
                Script = {
                            New-Upload -RawURL $Parameters.RawURL -HttpMethod GET -HttpListenerRequest $Parameters.HttpListenerRequest
                }
            },@{
                Path   = '/upload'
                Method = 'post'
                Script = {
                            New-Upload -RawURL $Parameters.RawURL -HttpMethod POST -HttpListenerRequest $Parameters.HttpListenerRequest
                }
            },@{
                Path   = '/vnc'
                method = 'get'
                Script = {
                            $ReturnObj = @{Exit = 0; Status = ''; Log = ''; LogOutput = ''}
                            if (Get-Process winvnc4 -ErrorAction SilentlyContinue) {
                                $ReturnObj.Exit = 1
                                $ReturnObj.Status = 'VNC is already running'
                            } else {
                                $CurrentLocation = (Get-Location).Path
                                if (Test-Path -Path "$($Env:SystemDrive)\TigerVNC\TigerVNC.bat" -PathType Leaf) {
                                    Set-Location "$($Env:SystemDrive)\TigerVNC"
                                    Start-Process -FilePath .\TigerVNC.bat -RedirectStandardOutput TigerVNC.log
                                    Set-Location $CurrentLocation
                                    $ReturnObj.Log = "$($Env:SystemDrive)\TigerVNC\TigerVNC.log"
                                    $StopWatch = New-Object -TypeName System.Diagnostics.Stopwatch
                                    $StopWatch.Start()
                                    while ($StopWatch.ElapsedMilliseconds -lt 5000 -and -not (Get-Process -Name winvnc4 -ErrorAction SilentlyContinue)) {
                                        Start-Sleep -Milliseconds 250
                                    }
                                    if (Get-Process -Name winvnc4 -ErrorAction SilentlyContinue) {
                                        $ReturnObj.Exit = 0
                                        $ReturnObj.Status = 'VNC process launched and running'
                                    } else {
                                        $ReturnObj.Exit = 2
                                        $ReturnObj.Status = 'VNC process launched, but is not running'
                                    }
                                    $ReturnObj.LogOutput = [String](Get-Content -Path "$($Env:SystemDrive)\TigerVNC\TigerVNC.log" -Raw)
                                } else {
                                    $ReturnObj.Exit = 3
                                    $ReturnObj.Status = 'Unable to locate executable'
                                }
                            }

                            Write-Output $ReturnObj | ConvertTo-Json -Depth 1
                }
            })
    
    if ($IncludeDefaultSchema) {
        if ($WebSchema.Count -eq 0) {
            $WebSchema = $DefaultSchema
        } else {
            $WebSchema += $DefaultSchema
        }
    }

    #  Convert WebSchema paths into REGEX for matching and pulling variables out of paths
    $WebSchema | %{$_.Path = "^$($_.Path)`$" -replace "\{", "(?<" -replace "\}", ">.*)"}
    #  Ensure all scripts are script blocks
    $WebSchema | %{if ($_.Script.GetType().FullName -ne 'System.Management.Automation.ScriptBlock'){$_.Script = [ScriptBlock]::Create($_.Script.ToString())}}
    #  Append parameters stuff onto the front of the script block
    $WebSchema | %{$_.Script = [ScriptBlock]::Create('param($parameters) ' + $_.Script.ToString())}
    #  Add values that don't need to be specified by default
    $WebSchema | %{if (-not ($_.ContainsKey('DefaultReply'))){$_['DefaultReply']=$True}}

    return $WebSchema
}


#  Return some basic system information as a PSObject
function Get-SystemInformation {
    # Support version for Lenovo devices as the Model
    if ((GWMI Win32_ComputerSystemProduct).vendor -eq 'lenovo') {
        $Model = (GWMI Win32_ComputerSystemProduct).Version
    }
    Else {
        #NOt Lenovo
        $Model = (GWMI Win32_ComputerSystem).Model
    }

    $OS  = (GWMI Win32_OperatingSystem).OSArchitecture
    $Manufacturer = (GWMI Win32_ComputerSystem).Manufacturer
    $UUID = (GWMI Win32_ComputerSystemProduct).UUID
    $NIC = @(GWMI Win32_NetworkAdapterConfiguration -Filter "IPEnabled = $true")
    $IP  = @($NIC | Select-Object -ExpandProperty IPAddress | Where-Object {$_.Length -le 15})
    $MAC = @($NIC | Select-Object -ExpandProperty MACAddress)

    try {
        $TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
        $TSEnvExists = $True
    } catch {
        $TSEnvExists = $False
    }

    $Computer = New-Object psobject -ArgumentList @{
                            IP = $IP;
                            MAC = $MAC
                            UUID = $UUID;
                            Arch = $OS;
                            Make = $Manufacturer;
                            Model = $Model;
                            TSEnvExists = $TSEnvExists
                        }
    
    $TSVars = @('_SMSTSMachineName',
    '_SMSTSMediaType',
    '_SMSTSBootUEFI',
    '_SMSTSAssignedSiteCode',
    '_SMSTSMP',
    '_SMSTSAdvertID',
    '_SMSTSPackageID',
    '_OSDRebootCount',
    '_SMSTSLastActionRetCode',
    '_SMSTSNextInstructionPointer',
    '_SMSTSInstructionTableSize',
    '_SMSTSLastActionSucceeded',
    '_SMSTSReserved1-000',
    '_SMSTSReserved2-000',
    '_SMSTSCurrentActionName')

    foreach ($TSVar in $TSVars) {
        if ($TSEnvExists) {
            [Void]($Computer | Add-Member -MemberType NoteProperty -Name $TSVar -Value $TSEnv.Value($TSVar))
        } else {
            [Void]($Computer | Add-Member -MemberType NoteProperty -Name $TSVar -Value '')
        }
    }
    return $Computer
}


#  Start the web server
#  Port specifies the TCP port to use
#  ShutdownCommand is a REGEX string that can match to the message body to shutdown the webserver.
#  For example:
#  Invoke-RestMethod -Uri http://localhost:8051/ -Method Post -Body 'ShutdownTheWebServerNow'
#  Leave ShutdownCommand empty to prevent shutting down in this method
#  WebSchema is an array of hashtables used to configure the server in different ways
function Start-PEHTTPServer {
    [cmdletbinding()]
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Int]$Port = 8000,
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [String]$ShutdownCommand = '^ShutdownTheWebServerNow',
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Object[]] $WebSchema = @(),
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Bool]$IncludeDefaultSchema = $True
    )

    $WebSchema = Update-WebSchema -WebSchema $WebSchema -IncludeDefaultSchema $IncludeDefaultSchema
    Write-Verbose "Configuring with web schema: `n$($WebSchema | Out-String)"

    #Create the Listener port
    try {
        $Listener = New-Object System.Net.Sockets.TcpListener -ArgumentList $Port
        #Start the listener; opens up port for incoming connections
        $Listener.Start()
    } catch {
        Write-Error $Error[0]
        Write-Error "Unable to create TCP listener with New-Object System.Net.Sockets.TcpListener -ArgumentList $($Port)"
        Return 1
    }

    Write-Verbose "Server started on port $($Port)"

	
    [HashTable]$SharedVariables = [hashtable]::Synchronized(@{})
    $SharedVariables['Listener'] = $Listener
    $SharedVariables['WebServerActive'] = $True
    $SharedVariables['WebSchema'] = $WebSchema
    $SharedVariables['ShutdownCommand'] = $ShutdownCommand
    $SharedVariables['Port'] = $Port
    $SharedVariables['VerbosePreference'] = $VerbosePreference
    [Int]$PreviousThreads = 0


    
    While ($SharedVariables['WebServerActive']) {
        Write-Verbose "Ready to accept TCP client on port $($Port)"
        try {
            $TcpClient = $Listener.AcceptTcpClient()
        } catch {
            Write-Error $Error[0]
            Write-Error 'Unable to accept new TCP clients with $Listener.AcceptTcpClient()'
            Return 1
        }

        $ClientIP = $TCPClient.client.RemoteEndPoint.Address.IPAddressToString
        Write-Verbose "New connection from $($ClientIP)"
        
        try {
            $Stream = $TcpClient.GetStream()
            Write-Verbose "Retrieved stream from $($ClientIP)"
        } catch {
            Write-Error $Error[0]
            Write-Error "Unable to get stream with `$TcpClient.GetStream() from $($ClientIP)"
            Return 1
        }

        #  Parse the incoming stream for HTTP data
        $HttpListenerRequest = Receive-HTTPData -TcpClient $TcpClient -Stream $Stream -SharedVariables $SharedVariables

        #  Execute HTTP request and respond if necessary
        if ($HttpListenerRequest.IsValid) {
            Execute-HTTPRequest -TcpClient $TcpClient -HttpListenerRequest $HttpListenerRequest -Stream $Stream -WebSchema $WebSchema -SharedVariables $SharedVariables
        } else {
            if ($HttpListenerRequest.HTTPBytes.Count -ne 0) {
                Write-Warning "Invalid HTTP Request from $($ClientIP) `n$($HttpListenerRequest | Out-String)"
            }
            $HTTPResponseBytes = New-HTTPResponseBytes
            Write-Verbose "Echoing $($HTTPResponseBytes.count) bytes to $($ClientIP)"
            $Stream.Write($HTTPResponseBytes,0,$HTTPResponseBytes.length)
        }

			   
        Write-Verbose "Closing session to $($ClientIP)"
        [Void]$Stream.Flush()
        [Void]$Stream.Dispose()
        [Void]$TCPClient.Close()

        #  Free up memory
        if (Test-Path Variable:\TcpClient) {
            Remove-Variable TcpClient
        }
        if (Test-Path Variable:\HttpListenerRequest) {
            Remove-Variable HttpListenerRequest
        }
        if (Test-Path Variable:\HTTPResponseBytes) {
            Remove-Variable HTTPResponseBytes
        }
        if (Test-Path Variable:\Stream) {
            Remove-Variable Stream
        }
        [System.GC]::Collect()

    }
    
    Write-Verbose "Stopping listener"
    [Void]$Listener.Stop()
}