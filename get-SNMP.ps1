<#	
    .NOTES
	=========================================================================================================
        Filename:	get-snmpdata-switch.ps1
        Version:	1.0
        Created:	12/31/2016
        Requires:       net-snmp for windows (http://net-snmp.sourceforge.net/)
	    Requires:       curl.exe for Windows (https://curl.haxx.se/download.html)
	    Requires:       InfluxDB 0.9.4 or later.  The latest is preferred.
        Requires:       Grafana 2.5 or later.  The latest is preferred.
        Prior Art:      Based on the linux script by Curt Dennis (https://git.denlab.io/dencur/grafana_scripts_public/blob/master/inetmon.sh)
        
	    Author:         Marc Dekeyser (a.k.a. Toasterlabs)
	    Blog:	https://geekswithblogs.net/marcde
	=========================================================================================================
	
    .SYNOPSIS
	Gathers snmp data using snmpget.exe and writes it to InfluxDB

    .DESCRIPTION
        This script supports InfluxDB 0.9.4 and later (including the latest 0.10.x).
        Please note that we use curl.exe for InfluxDB line protocol writes.  This means you must
        download curl.exe for Windows in order for Powershell to write to InfluxDB. In addition it requires
        net-snmp tools to retrieve the data.

        net-snmp does not provide binaries so you'll need to build the tools yourself. 

    .Usage
        Change the pluginpath, snmp version, community, snmp target to match your environment. At the end of the script, change
        InfluxDB-IP, InfluxDB-port & InfluxDB-Name to the values of your Influx DB Server and DB Name

        	    CurlPath = 'C:\Windows\System32\curl.exe';
                    Recommended curlpath

                $Data = C:\usr\bin\snmpwalk.exe -v <snmpversion> -c <communitystring> <IP> IF
                    Note that I filter for data starting with IF here. This reduced the runtime of the script considerably. 

                $CurlCommand  = "$($InfluxStruct.CurlPath) -i -XPOST http://<influxdbname>:<InfluxDBPost>/write?db=<influxDBDatabase> --data-binary '<measurementname>,Status=Eth$port value=$EthStatus'"
                $CurlCommand  = "$($InfluxStruct.CurlPath) -i -XPOST http://<influxdbname>:<InfluxDBPost>/write?db=<influxDBDatabase> --data-binary '<measurementname>,interface=Eth$port,direction=Inbound value=$EthInbps'"
                $CurlCommand  = "$($InfluxStruct.CurlPath) -i -XPOST http://<influxdbname>:<InfluxDBPost>/write?db=<influxDBDatabase> --data-binary '<measurementname>,interface=Eth$port,direction=Inbound value=$EthInbps'"
                    Change the <> in the script to match your setup

                $ports = 1..<Number of ports>
                    Change <> to match the number of ports on the device you are collecting against.
                    
    .EXAMPLE
        .\get-snmp.ps1

    .FUTURE
        I should really make use of those variables...


#>


# Reproducing grep
function grep {
  $input | out-string -stream | select-string $args
}

# Seconds to sleep between runs
$Sleeptime = '30'

# Suppressing any errors from showing up. 
$ErrorActionPreference="SilentlyContinue" 

# Influx Setup
    $InfluxStruct = New-Object -TypeName PSObject -Property @{
	    CurlPath = 'C:\Windows\System32\curl.exe';
        #InfluxDbServer = 'InfluxDB-IP'; #IP Address
        #InfluxDbPort = InfluxDB-port;
        #InfluxDbName = 'InfluxDB-Name';
        #InfluxDbUser = '';
        #InfluxDbPassword = '';
        MetricsString = '' #emtpy string that we populate later.
    }

# Number of Ports on Device    
$ports = 1..<Number of ports>

$InitialStatsIn = New-Object System.Collections.ArrayList
$InitialStatsOut = New-Object System.Collections.ArrayList

$Data = C:\usr\bin\snmpwalk.exe -v <snmpversion> -c <communitystring> <IP> IF

foreach ($port in $ports){

# Sorting through the data. \b Makes sure it's an exact match

$EthIn = ($data |grep "IF-MIB::IfInOctets.$port\b").ToString()
$ethOut = ($data |grep "IF-MIB::IfOutOctets.$port\b").ToString()

# Rightious headache right here. Output is in this format: IF-MIB::ifInOctets.28 = Counter32: 3573194510. Only interested in the last numbers. Lots of splits and a trim
# The ToString is because otherwise it won't apply...

$ethIn = ((($EthIn.split("="))[1]).split(':')[1]).Trim()
$ethOut = ((($EthOut.split("="))[1]).split(':')[1]).Trim()

$InitialStatsIn.Add($ethIn) > $null
$InitialStatsOut.Add($EthOut) > $null
}

DO{
    # Night Night
    Start-Sleep $Sleeptime

    $StatsIn = New-Object System.Collections.ArrayList
    $StatsOut = New-Object System.Collections.ArrayList

    $Data = C:\usr\bin\snmpwalk.exe -v <snmpversion> -c <communitystring> <IP> IF

    foreach ($port in $ports){

    # Sorting through the data. \b Makes sure it's an exact match

    $EthIn = ($data |grep "IF-MIB::IfInOctets.$port\b").ToString()
    $ethOut = ($data |grep "IF-MIB::IfOutOctets.$port\b").ToString()
    $EthStatus = ($data |grep "IF-MIB::ifOperStatus.$port\b").ToString()

    # Rightious headache right here. Output is in this format: IF-MIB::ifInOctets.28 = Counter32: 3573194510. Only interested in the last numbers. Lots of splits and a trim
    # The ToString is because otherwise it won't apply...

    $ethIn = ((($EthIn.split("="))[1]).split(':')[1]).Trim()
    $ethOut = ((($EthOut.split("="))[1]).split(':')[1]).Trim()
    $ethStatus = ((($EthStatus.split('='))[1]).split(':')[1]).Trim()

    # Writing data to Array
    $StatsIn.Add($ethIn) > $null
    $StatsOut.Add($EthOut) > $null
    
    # Defining Array position
    $ArrPos = $port - 1

    # Calculating current data
    $DiffEthIn = $StatsIn[$ArrPos] - $InitialStatsIn[$ArrPos]
    $DiffEthOut = $StatsOut[$ArrPos] - $InitialStatsOut[$ArrPos]

    # Calculating mbps
    $EthInbps = $DiffEthIn / $Sleeptime
    $EthOutBps = $DiffEthOut / $Sleeptime

    # Setting port status to up or down
    If($ethStatus -like "up*"){$EthStatus = 1}
    If($ethStatus -like "down*"){$EthStatus = 0}

    # Writing to shell
    Write-host "Eth$port Status: $EthStatus"
    Write-host "Current Eth$port Inbound traffic: $EthInbps bps"
    Write-host "Current Eth$port Outbound traffic: $ethOutbps bps"
        
    # Write to InfluxDB
    $CurlCommand  = "$($InfluxStruct.CurlPath) -i -XPOST http://<influxdbname>:<InfluxDBPost>/write?db=<influxDBDatabase> --data-binary '<measurementname>,Status=Eth$port value=$EthStatus'"
    Invoke-Expression -Command $CurlCommand 2>&1

    $CurlCommand  = "$($InfluxStruct.CurlPath) -i -XPOST http://<influxdbname>:<InfluxDBPost>/write?db=<influxDBDatabase> --data-binary '<measurementname>,interface=Eth$port,direction=Inbound value=$EthInbps'"
    Invoke-Expression -Command $CurlCommand 2>&1

    $CurlCommand  = "$($InfluxStruct.CurlPath) -i -XPOST http://<influxdbname>:<InfluxDBPost>/write?db=<influxDBDatabase> --data-binary '<measurementname>,interface=Eth$port,direction=Outbound value=$EthOutbps'"
    Invoke-Expression -Command $CurlCommand 2>&1

    }

    # Switching out data so loop can continue accuratly.
    $InitialStatsIn = $StatsIn
    $InitialStatsOut = $StatsOut


}While($strQuit -ne "N")

