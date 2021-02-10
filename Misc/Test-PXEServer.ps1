<#
Originating Author: Chris Dent from Origin
Date: 16/02/2010
Origin Source: https://www.indented.co.uk/dhcp-discovery/

A script to send a DHCPDISCOVER request and report on DHCPOFFER responses returned by all DHCP Servers on the current subnet.
Major Rework Author: Andreas Hammarskjöld @ 2Pint Software
Rework Date: 7/02/2017
http://2pintsoftware.com
Also adding PXE Option to discover ProxyDHCP servers.

Major Rework Author: Paul Bryson
https://github.com/Atamido/PowerShell/blob/master/Misc/Test-PXEServer.ps1
Also adding DHCP REQUEST

DHCP Packet Format (RFC 2131 - http://www.ietf.org/rfc/rfc2131.txt)
DHCP Option 93/97  (RFC 4578 - http://www.ietf.org/rfc/rfc4578.txt)


    DHCP Packet Format (RFC 2131 - http://www.ietf.org/rfc/rfc2131.txt):

    0                   1                   2                   3
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |     op (1)    |   htype (1)   |   hlen (1)    |   hops (1)    |
    +---------------+---------------+---------------+---------------+
    |                            xid (4)                            |
    +-------------------------------+-------------------------------+
    |           secs (2)            |           flags (2)           |
    +-------------------------------+-------------------------------+
    |                          ciaddr  (4)                          |
    +---------------------------------------------------------------+
    |                          yiaddr  (4)                          |
    +---------------------------------------------------------------+
    |                          siaddr  (4)                          |
    +---------------------------------------------------------------+
    |                          giaddr  (4)                          |
    +---------------------------------------------------------------+
    |                                                               |
    |                          chaddr  (16)                         |
    |                                                               |
    |                                                               |
    +---------------------------------------------------------------+
    |                                                               |
    |                          sname   (64)                         |
    +---------------------------------------------------------------+
    |                                                               |
    |                          file    (128)                        |
    +---------------------------------------------------------------+
    |                                                               |
    |                          options (variable)                   |
    +---------------------------------------------------------------+

    FIELD      OCTETS       DESCRIPTION
    -----      ------       -----------

    op            1  Message op code / message type.
                     1 = BOOTREQUEST, 2 = BOOTREPLY
    htype         1  Hardware address type, see ARP section in "Assigned
                     Numbers" RFC; e.g., '1' = 10mb ethernet.
    hlen          1  Hardware address length (e.g.  '6' for 10mb
                     ethernet).
    hops          1  Client sets to zero, optionally used by relay agents
                     when booting via a relay agent.
    xid           4  Transaction ID, a random number chosen by the
                     client, used by the client and server to associate
                     messages and responses between a client and a
                     server.
    secs          2  Filled in by client, seconds elapsed since client
                     began address acquisition or renewal process.
    flags         2  Flags (see figure 2).
    ciaddr        4  Client IP address; only filled in if client is in
                     BOUND, RENEW or REBINDING state and can respond
                     to ARP requests.
    yiaddr        4  'your' (client) IP address.
    siaddr        4  IP address of next server to use in bootstrap;
                     returned in DHCPOFFER, DHCPACK by server.
    giaddr        4  Relay agent IP address, used in booting via a
                     relay agent.
    chaddr       16  Client hardware address.
    sname        64  Optional server host name, null terminated string.
    file        128  Boot file name, null terminated string; "generic"
                     name or null in DHCPDISCOVER, fully qualified
                     directory-path name in DHCPOFFER.
    options     var  Optional parameters field.  See the options
                     documents for a list of defined options.


The DHCP Process is:
Client: DISCOVER broadcast
Server: OFFER, containing IP of DHCP server
Client: REQUEST, containing the ID of the DHCP server
Server: OFFER, containing available IP for client (This packet is optional, and the available client IP may instead be in the ACK packet)
Server: ACK, containing IP of PXE TFTP server and file path of boot image

#>

Function Test-PXESever {
    [cmdletbinding()]
    [Alias()]
    [OutputType([PSObject[]])]
    Param(
        # MAC Address and UUID are in Hex-Decimal Format, and can be delimited with dot, dash or colon (or none)
        [ValidatePattern('^((([a-f0-9]{2}[^a-z0-9]){5}[a-f0-9]{2})|([a-f0-9]{12}))$')]
        [String]$MacAddressString = @(Get-WmiObject Win32_NetworkAdapterConfiguration -Filter IPEnabled='True')[0].MACAddress,
        [ValidatePattern('^(([a-f0-9]{8}[^a-z0-9]([a-f0-9]{4}[^a-z0-9]){3}[a-f0-9]{12})|([a-f0-9]{32}))$')]
        [String]$UUIDString = (Get-WmiObject Win32_ComputerSystemProduct).UUID,
        #Possible Processor Architecture values here: https://www.iana.org/assignments/dhcpv6-parameters/processor-architecture.csv
        # x86-x64 Bios = 0
        # x86 UEFI = 6
        # x64 UEFI = 7
        # xEFIBC = 9
        [ValidateSet(0, 6, 7, 9)]
        [Int]$ProcessorArchitecture = 7,
        [String]$Option60String = "PXEClient",
        # Length of time (in seconds) to spend waiting for Offers if
        # the connection does not timeout first
        [Int]$DiscoverTimeout = 60
    )


    $TransactionID = New-Object Byte[] 4
    (New-Object Random).NextBytes($TransactionID)
    $TransactionIDString = ([String]::Join('', ($TransactionID | ForEach-Object { [String]::Format('{0:X2}', $_) })))
    Write-Verbose "Generated new TransactionID: $($TransactionIDString)"

    # Create a Byte Array for the DHCPDISCOVER packet
    [Byte[]]$Message = New-DhcpDiscoverPacket -MacAddressString $MacAddressString -UUIDString $UUIDString -ProcessorArchitecture $ProcessorArchitecture -Option60String $Option60String -TransactionID $TransactionID

    # Create a socket
    $UdpSocket = New-UdpSocket -SendTimeOut 10 -ReceiveTimeOut 10

    try {
        # UDP Port 68 (Server-to-Client port)
        $EndPoint = [Net.EndPoint](New-Object Net.IPEndPoint($([Net.IPAddress]::Any, 68)))
        # Listen on $EndPoint
        $UdpSocket.Bind($EndPoint)
    }
    catch {
        # Attempt to listen on specific IPv4 rather than 0.0.0.0:68 which may be taken by the DHCP service
        $IP = @(@(Get-WmiObject Win32_NetworkAdapterConfiguration -Filter IPEnabled='True')[0].IPAddress | Where-Object { $_.Length -lt 16 })[0]
        Write-Verbose "Attempting to open socket on $($IP):68"
        $EndPoint = [Net.EndPoint](New-Object Net.IPEndPoint($([Net.IPAddress]$IP, 68)))
        # Listen on $EndPoint
        $UdpSocket.Bind($EndPoint)
    }


    # UDP Port 67 (Client-to-Server port)
    $EndPoint = [Net.EndPoint](New-Object Net.IPEndPoint($([Net.IPAddress]::Broadcast, 67)))
    # Send the DHCPDISCOVER packet
    $BytesSent = $UdpSocket.SendTo($Message, $EndPoint)
    Write-Verbose "Broadcast $($BytesSent) byte DHCP DISCOVER message"

    # Begin receiving and processing responses
    [DateTime]$Start = Get-Date

    [Bool]$NoConnectionTimeOut = $true
    [Bool]$WaitingForDHCPPXE = $true
    [Bool]$WaitingForDHCPIP = $true
    [Bool]$WaitingForPXEResponse = $true
    [String]$PXEServerIP = ''

    While ($NoConnectionTimeOut) {
        $BytesReceived = 0
        Try {
            # Placeholder EndPoint for the Sender
            $SenderEndPoint = [Net.EndPoint](New-Object Net.IPEndPoint($([Net.IPAddress]::Any, 0)))
            # Receive Buffer
            $ReceiveBuffer = New-Object Byte[] 2048
            $BytesReceived = $UdpSocket.ReceiveFrom($ReceiveBuffer, [Ref]$SenderEndPoint)
        }
        #
        # Catch a SocketException, thrown when the Receive TimeOut value is reached
        #
        Catch [Net.Sockets.SocketException] {
            Write-Verbose "UDP socket timed out receiving with $($BytesReceived) bytes"
            if (-not $WaitingForPXEResponse) {
                Write-Verbose "Stopping as already received PXE response"
                break
            }
        }

        If ($BytesReceived -gt 0) {
            Write-Verbose "Received $($BytesReceived) bytes"
            $ParsedPacket = Read-DhcpPacket $ReceiveBuffer[0..($BytesReceived - 1)]
            $ParsedPacket | Write-Output

            if ($ParsedPacket.XID -ne $TransactionIDString) {
                Write-Warning "Received packet is for an unknown DHCP transaction"
            }

            #  Retrieve IP information
            if ($WaitingForDHCPIP -and
                $ParsedPacket.XID -eq $TransactionIDString -and
                ($ParsedPacket.Options | Where-Object { $_.OptionName -eq 'DhcpMessageType' } | Select-Object -Expand OptionValue) -eq 'DHCPOffer' -and
                $ParsedPacket.YIAddr -ne '0.0.0.0') {
                $WaitingForDHCPIP = $false
                Write-Verbose "Received DHCP OFFER for IP of $($ParsedPacket.YIAddr)"
                Write-Verbose ($ParsedPacket.Options | Where-Object { $_.OptionName -notin @('DhcpMessageType') } | Format-Table | Out-String)
            }

            #  Retrieve PXE information
            if (-not $WaitingForDHCPPXE -and
                $WaitingForPXEResponse -and
                $ParsedPacket.XID -eq $TransactionIDString -and
                ($ParsedPacket.Options | Where-Object { $_.OptionName -eq 'DhcpMessageType' } | Select-Object -Expand OptionValue) -eq 'DHCPACK' -and
                ($ParsedPacket.Options | Where-Object { $_.OptionName -eq 'VendorClassIdentifier' } | Select-Object -Expand OptionValue) -eq $Option60String -and
                $ParsedPacket.SIAddr -eq $PXEServerIP) {
                $WaitingForPXEResponse = $false
                Write-Verbose "Received DHCP ACK for PXE for server $($PXEServerIP) for file '$($ParsedPacket.File)'"
                Write-Verbose ($ParsedPacket.Options | Where-Object { $_.OptionName -notin @('DhcpMessageType', 'DhcpServerIdentifier') } | Format-Table | Out-String)
            }

            #  Send DHCP REQUEST when a DHCP OFFER is made for
            if ($WaitingForDHCPPXE -and
                $ParsedPacket.XID -eq $TransactionIDString -and
                ($ParsedPacket.Options | Where-Object { $_.OptionName -eq 'DhcpMessageType' } | Select-Object -Expand OptionValue) -eq 'DHCPOffer' -and
                ($ParsedPacket.Options | Where-Object { $_.OptionName -eq 'VendorClassIdentifier' } | Select-Object -Expand OptionValue) -eq $Option60String) {
                $WaitingForDHCPPXE = $false
                $PXEServerIP = $ParsedPacket.SIAddr
                Write-Verbose "Received DHCP OFFER for PXE for $($Option60String) from $($PXEServerIP)"
                [Byte[]]$Message = New-DhcpRequestPacket -MacAddressString $MacAddressString -UUIDString $UUIDString -ProcessorArchitecture $ProcessorArchitecture -Option60String $Option60String -TransactionID $TransactionID
                $BytesSent = $UdpSocket.SendTo($Message, $EndPoint)
                Write-Verbose "Broadcast $($BytesSent) byte DHCP REQUEST message"
            }
        }

        If ((Get-Date) -gt $Start.AddSeconds($DiscoverTimeout)) {
            # Exit condition, not error condition
            $NoConnectionTimeOut = $False
            Write-Verbose "Timed out waiting $($DiscoverTimeout) seconds for response"
        }
    }

    Remove-Socket $UdpSocket
}

#  Create the byte array for a an option in a DHCP packet

Function New-DhcpOption {
    [cmdletbinding()]
    [Alias()]
    [OutputType([Byte[]])]
    Param(
        [Parameter(ParameterSetName = 'ASCII', Mandatory = $true)]
        [Parameter(ParameterSetName = 'Hex', Mandatory = $true)]
        [Parameter(ParameterSetName = 'Int', Mandatory = $true)]
        [Parameter(ParameterSetName = 'ByteArray', Mandatory = $true)]
        [Byte]$Option,
        [Parameter(ParameterSetName = 'ASCII', Mandatory = $true)]
        [String]$ASCIIValue,
        [Parameter(ParameterSetName = 'Hex', Mandatory = $true)]
        [String]$HexValue,
        [Parameter(ParameterSetName = 'Int', Mandatory = $true)]
        [Int]$IntValue,
        [Parameter(ParameterSetName = 'ByteArray', Mandatory = $true)]
        [Byte[]]$ByteArray
    )

    if ($PSCmdlet.ParameterSetName -eq 'ASCII') {
        [Byte[]]$ByteArray = [System.Text.Encoding]::ASCII.GetBytes($ASCIIValue)
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Int' -or $PSCmdlet.ParameterSetName -eq 'Hex') {
        if ($PSCmdlet.ParameterSetName -eq 'Int') {
            $HexValue = ($IntValue).ToString('X')
        }
        else {
            $HexValue = $HexValue -replace '[^0-9a-f]', ''
        }

        if ($HexValue.Length % 2 -ne 0) {
            $HexValue = "0$($HexValue)"
        }

        [Byte[]]$ByteArray = [Byte[]]::New($HexValue.Length / 2)

        For ($i = 0; $i -lt $HexValue.Length; $i += 2) {
            $ByteArray[$i / 2] = [Convert]::ToByte($HexValue.Substring($i, 2), 16)
        }
    }

    [Byte[]]$ReturnBytes = [Byte[]]::New($ByteArray.Count + 2)
    $ReturnBytes[0] = $Option
    $ReturnBytes[1] = $ByteArray.Count
    if ($ByteArray.Count -gt 0) {
        $ByteArray.CopyTo($ReturnBytes, 2)
    }

    return $ReturnBytes
}

# Build a DHCPDISCOVER packet to send

Function New-DhcpDiscoverPacket {
    [cmdletbinding()]
    [Alias()]
    [OutputType([Byte[]])]
    Param(
        # MAC Address and UUID are in Hex-Decimal Format, and can be delimited with dot, dash or colon (or none)
        [ValidatePattern('^((([a-f0-9]{2}[^a-z0-9]){5}[a-f0-9]{2})|([a-f0-9]{12}))$')]
        [String]$MacAddressString = @(Get-WmiObject Win32_NetworkAdapterConfiguration -Filter IPEnabled='True')[0].MACAddress,
        [ValidatePattern('^(([a-f0-9]{8}[^a-z0-9]([a-f0-9]{4}[^a-z0-9]){3}[a-f0-9]{12})|([a-f0-9]{32}))$')]
        [String]$UUIDString = (Get-WmiObject Win32_ComputerSystemProduct).UUID,
        #Possible Processor Architecture values here: https://www.iana.org/assignments/dhcpv6-parameters/processor-architecture.csv
        # x86-x64 Bios = 0
        # x86 UEFI = 6
        # x64 UEFI = 7
        # xEFIBC = 9
        [ValidateSet(0, 6, 7, 9)]
        [Int]$ProcessorArchitecture = 0,
        [String]$Option60String = "PXEClient",
        [Byte[]]$TransactionID
    )

    Write-Verbose "Creating DhcpDiscoverPacket with MAC $($MacAddressString) and UUID $($UUIDString)"
    # Generate a Transaction ID for this request
    if (-not ($TransactionID) -or $TransactionID.Count -ne 4) {
        $TransactionID = New-Object Byte[] 4
        (New-Object Random).NextBytes($TransactionID)
        Write-Verbose "Generated new TransactionID: $($TransactionID | ForEach-Object {("{0:X2} " -f [int]$_) })"
    }

    # Convert the MAC Address String into a Byte Array

    # Drop any characters which might be used to delimit the string
    $MacAddressString = $MacAddressString -replace '[^0-9a-f]'

    $MacAddress = [BitConverter]::GetBytes(([UInt64]::Parse($MacAddressString, [Globalization.NumberStyles]::HexNumber)))
    # Reverse the MAC Address array
    [Array]::Reverse($MacAddress)

    # Create the Byte Array
    $DhcpDiscover = New-Object Byte[] 240

    # Copy the MacAddress Bytes into the array (drop the first 2 bytes,
    # too many bytes returned from UInt64)
    [Array]::Copy($MACAddress, 2, $DhcpDiscover, 28, 6)

    # Set the OP Code to BOOTREQUEST
    $DhcpDiscover[0] = 1
    # Set the Hardware Address Type to Ethernet
    $DhcpDiscover[1] = 1
    # Set the Hardware Address Length (number of bytes)
    $DhcpDiscover[2] = 6
    # Copy the Transaction ID Bytes into the array
    [Array]::Copy($TransactionID, 0, $DhcpDiscover, 4, 4)
    # Set the Broadcast Flag
    $DhcpDiscover[10] = 128
    # Set the Magic Cookie values
    $DhcpDiscover[236] = 99
    $DhcpDiscover[237] = 130
    $DhcpDiscover[238] = 83
    $DhcpDiscover[239] = 99

    #  MessageType: DISCOVER
    $DhcpDiscover += New-DhcpOption -Option 53 -IntValue 1

    # MaxDHCPMessageSize: 1472 bytes
    $DhcpDiscover += New-DhcpOption -Option 57 -IntValue 1472

    #  ParameterRequestList:
    #  This is what Hyper-V guests send by default
    [Byte[]]$PRL = @()
    $PRL += 1 #  Subnet Mas
    $PRL += 2 #  Time Offset
    $PRL += 3 #  Router
    $PRL += 4 #  Time Server
    $PRL += 5 #  Name Server
    $PRL += 6 #  Domain Name Server
    $PRL += 12 #  Host Name
    $PRL += 13 #  Boot File Size
    $PRL += 15 #  Domain Name
    $PRL += 17 #  Root Path
    $PRL += 18 #  Extensions Path
    $PRL += 22 #  Maximum Datagram Reasembly Size
    $PRL += 23 #  Default IP Time-to-live
    $PRL += 28 #  Broadcast Address
    $PRL += 40 #  Network Information Service Domain
    $PRL += 41 #  Network Information Servers
    $PRL += 42 #  Network Time Protocol Servers
    $PRL += 43 #  Vendor specific information
    $PRL += 50 #  Requested IP Address
    $PRL += 51 #  IP Address Lease Time
    $PRL += 54 #  Server Identifier
    $PRL += 58 #  Renewal (T1) Time Value
    $PRL += 59 #  Rebinding (T2) Time Value
    $PRL += 60 #  Class-identifier
    $PRL += 66 #  TFTP Server Name
    $PRL += 67 #  Bootfile Name
    $PRL += 97 #  UUID/GUID based Client Identifier
    $PRL += 128 #  Unknown
    $PRL += 129 #  Unknown
    $PRL += 130 #  Unknown
    $PRL += 131 #  Unknown
    $PRL += 132 #  Unknown
    $PRL += 133 #  Unknown
    $PRL += 134 #  Unknown
    $PRL += 135 #  Unknown
    $DhcpDiscover += New-DhcpOption -Option 55 -ByteArray $PRL

    #  GeneralOption: UUID/GUID based Client Identifier
    #  Byte order of this value appears to have some swapping going on
    #  This is the before and after ordering
    #  0123-45-67-89-ABCDEF
    #  3210-54-76-89-ABCDEF
    #  The final value is then left padded with a zero byte
    #  Remove dashes and other characters
    [String]$UUIDMod = $UUIDString -replace '[^0-9a-f]'
    #  Swap first set of bytes
    $UUIDMod = $UUIDMod -replace '(..)(..)(..)(..)(..)(..)(..)(..)(.{16})', '$4$3$2$1$6$5$8$7$9'
    $UUIDMod = "00$($UUIDMod)"
    $DhcpDiscover += New-DhcpOption -Option 97 -HexValue $UUIDMod

    #  GeneralOption: Client Network Device Interface (UNDI).  Have also seen this set to '01 03 10'
    $DhcpDiscover += New-DhcpOption -Option 94 -HexValue '01 03 00'

    #  GeneralOption: Client System
    $DhcpDiscover += New-DhcpOption -Option 93 -HexValue "00 0$($ProcessorArchitecture)"

    #  DHCPEOptionsVendorClassIdentifier.  Have also seen the UNDI portion set to 003016
    $DhcpDiscover += New-DhcpOption -Option 60 -ASCIIValue "$($Option60String):Arch:0000$($ProcessorArchitecture):UNDI:003000"

    #  DHCP Options end in FF
    $DhcpDiscover += 255

    Return $DhcpDiscover
}

# Build a DHCPREQUEST packet to send

Function New-DhcpRequestPacket {
    [cmdletbinding()]
    [Alias()]
    [OutputType([Byte[]])]
    Param(
        # MAC Address and UUID are in Hex-Decimal Format, and can be delimited with dot, dash or colon (or none)
        [ValidatePattern('^((([a-f0-9]{2}[^a-z0-9]){5}[a-f0-9]{2})|([a-f0-9]{12}))$')]
        [String]$MacAddressString = @(Get-WmiObject Win32_NetworkAdapterConfiguration -Filter IPEnabled='True')[0].MACAddress,
        [ValidatePattern('^(([a-f0-9]{8}[^a-z0-9]([a-f0-9]{4}[^a-z0-9]){3}[a-f0-9]{12})|([a-f0-9]{32}))$')]
        [String]$UUIDString = (Get-WmiObject Win32_ComputerSystemProduct).UUID,
        #Possible Processor Architecture values here: https://www.iana.org/assignments/dhcpv6-parameters/processor-architecture.csv
        # x86-x64 Bios = 0
        # x86 UEFI = 6
        # x64 UEFI = 7
        # xEFIBC = 9
        [ValidateSet(0, 6, 7, 9)]
        [Int]$ProcessorArchitecture = 0,
        [String]$Option60String = "PXEClient",
        [Byte[]]$TransactionID
    )

    Write-Verbose "Creating DhcpRequestPacket with MAC $($MacAddressString) and UUID $($UUIDString)"
    # Generate a Transaction ID for this request
    if (-not ($TransactionID) -or $TransactionID.Count -ne 4) {
        $TransactionID = New-Object Byte[] 4
        (New-Object Random).NextBytes($TransactionID)
        Write-Verbose "Generated new TransactionID: $($TransactionID | ForEach-Object {("{0:X2} " -f [int]$_) })"
    }

    # Convert the MAC Address String into a Byte Array

    # Drop any characters which might be used to delimit the string
    $MacAddressString = $MacAddressString -replace '[^0-9a-f]'

    $MacAddress = [BitConverter]::GetBytes(([UInt64]::Parse($MacAddressString, [Globalization.NumberStyles]::HexNumber)))
    # Reverse the MAC Address array
    [Array]::Reverse($MacAddress)

    # Create the Byte Array
    $DhcpDiscover = New-Object Byte[] 240

    # Copy the MacAddress Bytes into the array (drop the first 2 bytes,
    # too many bytes returned from UInt64)
    [Array]::Copy($MACAddress, 2, $DhcpDiscover, 28, 6)

    # Set the OP Code to BOOTREQUEST
    $DhcpDiscover[0] = 1
    # Set the Hardware Address Type to Ethernet
    $DhcpDiscover[1] = 1
    # Set the Hardware Address Length (number of bytes)
    $DhcpDiscover[2] = 6
    # Copy the Transaction ID Bytes into the array
    [Array]::Copy($TransactionID, 0, $DhcpDiscover, 4, 4)
    # Set the Broadcast Flag
    $DhcpDiscover[10] = 128
    # Set the Magic Cookie values
    $DhcpDiscover[236] = 99
    $DhcpDiscover[237] = 130
    $DhcpDiscover[238] = 83
    $DhcpDiscover[239] = 99

    #  MessageType: REQUEST
    $DhcpDiscover += New-DhcpOption -Option 53 -IntValue 3

    # MaxDHCPMessageSize: 1472 bytes
    $DhcpDiscover += New-DhcpOption -Option 57 -IntValue 32000

    #  ParameterRequestList:
    #  This is what Hyper-V guests send by default
    [Byte[]]$PRL = @()
    $PRL += 1 #  Subnet Mas
    $PRL += 2 #  Time Offset
    $PRL += 3 #  Router
    $PRL += 4 #  Time Server
    $PRL += 5 #  Name Server
    $PRL += 6 #  Domain Name Server
    $PRL += 12 #  Host Name
    $PRL += 13 #  Boot File Size
    $PRL += 15 #  Domain Name
    $PRL += 17 #  Root Path
    $PRL += 18 #  Extensions Path
    $PRL += 22 #  Maximum Datagram Reasembly Size
    $PRL += 23 #  Default IP Time-to-live
    $PRL += 28 #  Broadcast Address
    $PRL += 40 #  Network Information Service Domain
    $PRL += 41 #  Network Information Servers
    $PRL += 42 #  Network Time Protocol Servers
    $PRL += 43 #  Vendor specific information
    $PRL += 50 #  Requested IP Address
    $PRL += 51 #  IP Address Lease Time
    $PRL += 54 #  Server Identifier
    $PRL += 58 #  Renewal (T1) Time Value
    $PRL += 59 #  Rebinding (T2) Time Value
    $PRL += 60 #  Class-identifier
    $PRL += 66 #  TFTP Server Name
    $PRL += 67 #  Bootfile Name
    $PRL += 97 #  UUID/GUID based Client Identifier
    $PRL += 128 #  Unknown
    $PRL += 129 #  Unknown
    $PRL += 130 #  Unknown
    $PRL += 131 #  Unknown
    $PRL += 132 #  Unknown
    $PRL += 133 #  Unknown
    $PRL += 134 #  Unknown
    $PRL += 135 #  Unknown
    $DhcpDiscover += New-DhcpOption -Option 55 -ByteArray $PRL

    #  GeneralOption: UUID/GUID based Client Identifier
    #  Byte order of this value appears to have some swapping going on
    #  This is the before and after ordering
    #  0123-45-67-89-ABCDEF
    #  3210-54-76-89-ABCDEF
    #  The final value is then left padded with a zero byte
    #  Remove dashes and other characters
    [String]$UUIDMod = $UUIDString -replace '[^0-9a-f]'
    #  Swap first set of bytes
    $UUIDMod = $UUIDMod -replace '(..)(..)(..)(..)(..)(..)(..)(..)(.{16})', '$4$3$2$1$6$5$8$7$9'
    $UUIDMod = "00$($UUIDMod)"
    $DhcpDiscover += New-DhcpOption -Option 97 -HexValue $UUIDMod

    #  GeneralOption: Client Network Device Interface
    $DhcpDiscover += New-DhcpOption -Option 94 -HexValue '01 03 00'

    #  GeneralOption: Client System
    $DhcpDiscover += New-DhcpOption -Option 93 -HexValue "00 0$($ProcessorArchitecture)"

    #  DHCPEOptionsVendorClassIdentifier
    $DhcpDiscover += New-DhcpOption -Option 60 -ASCIIValue "$($Option60String):Arch:0000$($ProcessorArchitecture):UNDI:003000"

    #  DHCP Options end in FF
    $DhcpDiscover += 255

    Return $DhcpDiscover
}

# Parse a DHCP Packet, returning an object containing each field

Function Read-DhcpPacket {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateCount(240, 2048)]
        [Byte[]]$Packet
    )
    $Reader = New-Object IO.BinaryReader(New-Object IO.MemoryStream(@(, $Packet)))

    $DhcpResponse = New-Object Object

    # Get and translate the Op code
    $DhcpResponse | Add-Member NoteProperty Op $Reader.ReadByte()
    if ($DhcpResponse.Op -eq 1) {
        $DhcpResponse.Op = "BootRequest"
    }
    else {
        $DhcpResponse.Op = "BootResponse"
    }

    $DhcpResponse | Add-Member NoteProperty HType -Value $Reader.ReadByte()
    if ($DhcpResponse.HType -eq 1) { $DhcpResponse.HType = "Ethernet" }

    $DhcpResponse | Add-Member NoteProperty HLen $Reader.ReadByte()
    $DhcpResponse | Add-Member NoteProperty Hops $Reader.ReadByte()
    $DhcpResponse | Add-Member NoteProperty XID ([String]::Join('', ($Reader.ReadBytes(4) | ForEach-Object { [String]::Format('{0:X2}', $_) })))
    $DhcpResponse | Add-Member NoteProperty Secs $Reader.ReadUInt16()
    $DhcpResponse | Add-Member NoteProperty Flags $Reader.ReadUInt16()
    # Broadcast is the only flag that can be present, the other bits are reserved
    if ($DhcpResponse.Flags -BAnd 128) { $DhcpResponse.Flags = @("Broadcast") }

    $DhcpResponse | Add-Member NoteProperty CIAddr `
    $("$($Reader.ReadByte()).$($Reader.ReadByte())." + `
            "$($Reader.ReadByte()).$($Reader.ReadByte())")
    $DhcpResponse | Add-Member NoteProperty YIAddr `
    $("$($Reader.ReadByte()).$($Reader.ReadByte())." + `
            "$($Reader.ReadByte()).$($Reader.ReadByte())")
    $DhcpResponse | Add-Member NoteProperty SIAddr `
    $("$($Reader.ReadByte()).$($Reader.ReadByte())." + `
            "$($Reader.ReadByte()).$($Reader.ReadByte())")
    $DhcpResponse | Add-Member NoteProperty GIAddr `
    $("$($Reader.ReadByte()).$($Reader.ReadByte())." + `
            "$($Reader.ReadByte()).$($Reader.ReadByte())")

    $MacAddrBytes = New-Object Byte[] 16
    [Void]$Reader.Read($MacAddrBytes, 0, 16)
    $MacAddress = [String]::Join(
        ":", $($MacAddrBytes[0..5] | ForEach-Object { [String]::Format('{0:X2}', $_) }))
    $DhcpResponse | Add-Member NoteProperty CHAddr $MacAddress

    $DhcpResponse | Add-Member NoteProperty SName `
    $([String]::Join("", $Reader.ReadChars(64)).Replace("`0", '').Trim())
    $DhcpResponse | Add-Member NoteProperty File `
    $([String]::Join("", $Reader.ReadChars(128)).Replace("`0", '').Trim())

    $DhcpResponse | Add-Member NoteProperty MagicCookie `
    $("$($Reader.ReadByte()).$($Reader.ReadByte())." + `
            "$($Reader.ReadByte()).$($Reader.ReadByte())")

    # Start reading Options

    $DhcpResponse | Add-Member NoteProperty Options @()
    While ($Reader.BaseStream.Position -lt $Reader.BaseStream.Length) {
        $Option = New-Object Object
        $Option | Add-Member NoteProperty OptionCode $Reader.ReadByte()
        $Option | Add-Member NoteProperty OptionName ""
        $Option | Add-Member NoteProperty Length 0
        $Option | Add-Member NoteProperty OptionValue ""

        If ($Option.OptionCode -ne 0 -And $Option.OptionCode -ne 255) {
            $Option.Length = $Reader.ReadByte()
        }

        Switch ($Option.OptionCode) {
            0 { $Option.OptionName = "PadOption" }
            1 {
                $Option.OptionName = "SubnetMask"
                $Option.OptionValue = `
                $("$($Reader.ReadByte()).$($Reader.ReadByte())." + `
                        "$($Reader.ReadByte()).$($Reader.ReadByte())")
            }
            3 {
                $Option.OptionName = "Router"
                $Option.OptionValue = `
                $("$($Reader.ReadByte()).$($Reader.ReadByte())." + `
                        "$($Reader.ReadByte()).$($Reader.ReadByte())")
            }
            6 {
                $Option.OptionName = "DomainNameServer"
                $Option.OptionValue = @()
                For ($i = 0; $i -lt ($Option.Length / 4); $i++) {
                    $Option.OptionValue += `
                    $("$($Reader.ReadByte()).$($Reader.ReadByte())." + `
                            "$($Reader.ReadByte()).$($Reader.ReadByte())")
                }
            }
            15 {
                $Option.OptionName = "DomainName"
                $Option.OptionValue = [String]::Join(
                    "", $Reader.ReadChars($Option.Length))
            }
            28 {
                $Option.OptionName = "BroadcastAddress"
                $Option.OptionValue = `
                $("$($Reader.ReadByte()).$($Reader.ReadByte())." + `
                        "$($Reader.ReadByte()).$($Reader.ReadByte())")
            }
            42 {
                $Option.OptionName = "NTPServer"
                $Option.OptionValue = @()
                For ($i = 0; $i -lt ($Option.Length / 4); $i++) {
                    $Option.OptionValue += `
                    $("$($Reader.ReadByte()).$($Reader.ReadByte())." + `
                            "$($Reader.ReadByte()).$($Reader.ReadByte())")
                }
            }
            51 {
                $Option.OptionName = "IPAddressLeaseTime"
                # Read as Big Endian
                $Value = ($Reader.ReadByte() * [Math]::Pow(256, 3)) + `
                ($Reader.ReadByte() * [Math]::Pow(256, 2)) + `
                ($Reader.ReadByte() * 256) + `
                    $Reader.ReadByte()
                $Option.OptionValue = $(New-TimeSpan -Seconds $Value)
            }
            53 {
                #  https://www.iana.org/assignments/bootp-dhcp-parameters/bootp-dhcp-parameters.xhtml
                $Option.OptionName = "DhcpMessageType"
                Switch ($Reader.ReadByte()) {
                    1 { $Option.OptionValue = "DHCPDISCOVER" }
                    2 { $Option.OptionValue = "DHCPOFFER" }
                    3 { $Option.OptionValue = "DHCPREQUEST" }
                    4 { $Option.OptionValue = "DHCPDECLINE" }
                    5 { $Option.OptionValue = "DHCPACK" }
                    6 { $Option.OptionValue = "DHCPNAK" }
                    7 { $Option.OptionValue = "DHCPRELEASE" }
                }
            }
            54 {
                $Option.OptionName = "DhcpServerIdentifier"
                $Option.OptionValue = `
                $("$($Reader.ReadByte()).$($Reader.ReadByte())." + `
                        "$($Reader.ReadByte()).$($Reader.ReadByte())")
            }
            58 {
                $Option.OptionName = "RenewalTime"
                # Read as Big Endian
                $Value = ($Reader.ReadByte() * [Math]::Pow(256, 3)) + `
                ($Reader.ReadByte() * [Math]::Pow(256, 2)) + `
                ($Reader.ReadByte() * 256) + `
                    $Reader.ReadByte()
                $Option.OptionValue = $(New-TimeSpan -Seconds $Value)
            }
            59 {
                $Option.OptionName = "RebindingTime"
                # Read as Big Endian
                $Value = ($Reader.ReadByte() * [Math]::Pow(256, 3)) + `
                ($Reader.ReadByte() * [Math]::Pow(256, 2)) + `
                ($Reader.ReadByte() * 256) + `
                    $Reader.ReadByte()
                $Option.OptionValue = $(New-TimeSpan -Seconds $Value)
            }
            60 {
                $Option.OptionName = "VendorClassIdentifier"
                $Option.OptionValue = [String]::Join(
                    "", $Reader.ReadChars($Option.Length))
            }
            67 {
                $Option.OptionName = "vendor-class-identifier"
                # Read as Big Endian
                $Value = ($Reader.ReadByte() * [Math]::Pow(256, 3)) + `
                ($Reader.ReadByte() * [Math]::Pow(256, 2)) + `
                ($Reader.ReadByte() * 256) + `
                    $Reader.ReadByte()
                $Option.OptionValue = $(New-TimeSpan -Seconds $Value)
            }
            97 {
                $Option.OptionName = "UUID"
                $ByteValue = $Reader.ReadBytes($Option.Length)
                #  Convert to hex string, skipping first character
                [String]$StringValue = @($ByteValue[1..$ByteValue.Count] | ForEach-Object { ("{0:X2}" -f [int]$_) }) -join ''
                #  Rearrange some of the characters
                $StringValue = $StringValue -replace '(..)(..)(..)(..)(..)(..)(..)(..)(.{16})', '$4$3$2$1$6$5$8$7$9'
                #  Add hyphens in the appropriate places
                $Option.OptionValue = $StringValue -replace '(.{8})(.{4})(.{4})(.{4})(.{12})', '$1-$2-$3-$4-$5'
            }
            252 {
                $Option.OptionName = "WPAD"
                $Option.OptionValue = [String]::Join(
                    "", $Reader.ReadChars($Option.Length))
            }
            255 { $Option.OptionName = "EndOption" }
            default {
                # For all options which are not decoded here
                $Option.OptionName = "NoOptionDecode"
                $Buffer = New-Object Byte[] $Option.Length
                [Void]$Reader.Read($Buffer, 0, $Option.Length)
                $Option.OptionValue = $Buffer
            }
        }

        if ($Option.OptionName -eq 'NoOptionDecode') {
            $DhcpResponse.Options += $Option

            $Option2 = New-Object Object
            $Option2 | Add-Member NoteProperty OptionCode $Option.OptionCode
            $Option2 | Add-Member NoteProperty OptionName 'NoOptionDecode-String'
            $Option2 | Add-Member NoteProperty Length 0
            $Option2 | Add-Member NoteProperty OptionValue ([System.Text.Encoding]::ASCII.GetString(@($Option.OptionValue | Where-Object { $_ -gt 31 -and $_ -lt 127 })))
            $Option2.Length = $Option2.OptionValue.Length
            $DhcpResponse.Options += $Option2

        }
        elseif ($Option.OptionName -notin @('PadOption', 'EndOption')) {
            # Override the ToString method
            $Option | Add-Member ScriptMethod ToString `
            { Return "$($this.OptionName) ($($this.OptionValue))" } -Force

            $DhcpResponse.Options += $Option
        }
    }

    Return $DhcpResponse

}

# Create a UDP Socket with Broadcast and Address Re-use enabled.

Function New-UdpSocket {
    [cmdletbinding()]
    [Alias()]
    [OutputType([Net.Sockets.Socket])]
    Param(
        [Parameter(Mandatory = $false)]
        [Int32]$SendTimeOut = 5,
        [Parameter(Mandatory = $false)]
        [Int32]$ReceiveTimeOut = 5
    )

    $UdpSocket = New-Object Net.Sockets.Socket(
        [Net.Sockets.AddressFamily]::InterNetwork,
        [Net.Sockets.SocketType]::Dgram,
        [Net.Sockets.ProtocolType]::Udp)
    $UdpSocket.EnableBroadcast = $True
    $UdpSocket.ExclusiveAddressUse = $False
    $UdpSocket.SendTimeOut = $SendTimeOut * 1000
    $UdpSocket.ReceiveTimeOut = $ReceiveTimeOut * 1000

    Return $UdpSocket
}

# Close down a Socket

Function Remove-Socket {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [Net.Sockets.Socket]$Socket
    )

    $Socket.Shutdown("Both")
    $Socket.Close()
}


$Packets = @()

Write-Host "Testing BIOS"
$Packets += Test-PXESever -ProcessorArchitecture 0 -Verbose

Write-Host "Testing x64 UEFI"
$Packets += Test-PXESever -ProcessorArchitecture 7 -Verbose

Write-Host "Received $($Packets.Count) packets"

Write-Output $Packets
