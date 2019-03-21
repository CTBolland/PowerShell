#REQUIRES -Version 2.0
<# 
.SYNOPSIS
    Group Shutdown of Virtual and Physical Servers, via the Hosts.
    
.DESCRIPTION
    Pulls from a CSV list and shuts down servers. If Server is a Hyper-V VM, it sends a "Stop-VM $name" command 
    to the host. This way the script need not connect to every single VM, but simply connect to their host/cluster. 
    It first checks if the VM is located on a Cluster, which are defiend at the top of the script. 
    This is done for security reasons, and ease of management. Make sure that if targeting VM's hoted on a cluster 
    that you run this script from a machine that has the Failover Remote Management Tools installed, otherwise the
    Cluster-related commands will fail.
    
    If it's a physical box, it sends a "shutdown -s -m \\$name". Note: This command requires that the physical 
    server is configured to allow WMI through the firewall.
    
    This script is best used in conjunction with task scheduler, or paired with a power management solution such 
    as Eaton.   
    
.INPUTS
    This CSV that contains all the device information should have the following columns:
        name --- Device name
        ip ----- IP address of device
        type --- Host or Guest
        host --- If type is guest, then host/cluster name goes here
        group -- Assign device to a group. These groups are used to target collections of devices

    Example CSV:

    name        ip              type    host        group
    ---------------------------------------------------
    Server01    192.168.0.10     host                B
    vm01        192.168.0.20     guest   Server01    A   
    vm02        192.168.0.30     guest   Server01    A
    
.PARAMETER group
    Target specifc groups within the csv  
    
.EXAMPLE
    Shutdown group A, which is comprised of the guests running on Server01:
        .\Group-Shutdown.ps1 -group "A"

    Shutdown group B, which is the host:
        .\Group-Shutdown.ps1 -group "B"

.NOTES       
    AUTHOR:         Craig Bolland
    CREATED:        02-26-2019 
    UPDATED:        03-19-2019 
#> 
# ---------------------------------------------------------- 
param (
    [string]$group
)  

$deviceList = "c:\temp\servers.csv"
$logFolder = "c:\temp\logs"
$log = ("$logFolder\Server-Shutdown-Log-" + (Get-Date).tostring("MM-dd-yyyy") + ".txt")
$clusters = @("cluster1", "cluster2")
$pTypes = @("host", "physical", "cluster*")
$guest = "guest"

$log = ("$logFolder\Server-Shutdown-Log-" + (Get-Date).tostring("MM-dd-yyyy") + ".txt")
if(!(Test-Path -Path $log )){New-Item -ItemType File -Path $log}

function Write-Log {
    param (      
        [string]$status,
        [string]$Message
    )    
    $time = "{0:HH:mm:ss}" -f (Get-Date)
    $line = [pscustomobject]@{
        'DateTime' = $time
        'Status' = $status
        'Group' = $group
        'Name' = $name
        'Type' = $type
        'Host' = $hoster
        'IP' = $ip
        'Message' = $Message    
    }   
    $line | Export-Csv -Path $Log -Append -NoTypeInformation
}

# select all devices in the specified group
$servers = Import-Csv -Path $deviceList| Where-Object {$_.Group -eq $group} 
foreach ($server in $servers) {
    # csv variables
    $ip = $server.ip
    $name = $server.name
    $type = $server.type
    $hoster = $server.host
    
# determine if VM is on cluster or standalone server host:
    # if hosted in a failover cluster:
    if (($type -eq $guest) -and ($hoster -in $clusters)) {
        # find and shut down vm on whatever node it is currently on
        Get-ClusterNode –Cluster $hoster | Get-ClusterResource -Name *$name | Get-VM | Stop-VM -Force -WarningVariable a
        if ($a -eq $null) { Write-Log -status "SHUTDOWN" -Message "Shutdown Initiated" } else { Write-Log -status "OFFLINE" -message $a }
    } 
    # if hosted on a standalone host:
    elseif (($type -eq $guest) -and ($hoster -notin $clusters)) {
        Stop-VM –Name $name –ComputerName ($hoster) -Force -WarningVariable a
        if ($a -eq $null) { Write-Log -status "SHUTDOWN" -Message "Shutdown Initiated"  } else { Write-Log -status "OFFLINE" -message $a }
    }

# If the device is a physical server:
    elseif ($type -in $pTypes) {
        # shutdown command
        shutdown -s -m \\$ip -t 1 /f
        # error and is pingable:
        if ($LastExitCode -ne 0 -And (Test-Connection -computername $ip -Quiet -Count 1)) {
            Write-Log -status "MISCONFIGURED" -Message "Error Code($LastExitCode)"
        }
        # error and is not pingable:
        elseif ($LastExitCode -ne 0 -And (!(Test-Connection -computername $ip -Quiet -Count 1))) {
            Write-Log -status "OFFLINE" -message "Computer already powered off"
        }
        # no error:
        else { 
            Write-Log -status "ACCEPTED" -message "Shutdown Initiated"
        }
    }
}


