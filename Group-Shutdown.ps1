#REQUIRES -Version 2.0
<# 
.SYNOPSIS
    Group Shutdown of Virtual and Physical Servers, via the Hosts.
    
.DESCRIPTION
    Pulls from a CSV list and shuts down servers. If Server is a Hyper-V VM, it sends a "Stop-VM $name" command 
    to the host. This way the script need not connect to every single VM, but simply connect to their host/cluster. 
    It first checks if the VM is located on a Cluster, which are defiend at the top of the script. 
    This is done for security reasons, and ease of management. 
    
    If it's a physical box, it sends a "shutdown -s -m \\$name". Note: This command requires that the physical 
    server is configured to allow remote shutdown. 
    
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
param ([string]$group)  

$list = "c:\Temp\Servers.csv"
$logPath = "c:\Temp\logs"
$clusters = @("clusterA", "clusterB") # <--add or $null failover clusters here

# create date-samped log file if one doesnt exist.
$log = "$logPath\Server-Shutdown-Log-" + (Get-Date).tostring("MM-dd-yyyy") + ".txt" 
if(!(Test-Path -Path $log )){New-Item -ItemType File -Path $log}

# log function
function Write-Log {
    param ([string]$Message)  
    $time = "[{0:HH:mm:ss}]" -f (Get-Date)
    Write-Output "$($time)Group[$group]-[$ip]-[$hostName]-[$name] $message"| Out-file $log  -Append -Force
}

# select all devices in the specified group
$servers = Import-Csv -Path $list| Where-Object {$_.Group -eq $group} 
foreach ($server in $servers) {
# pull variables from CSV columns
    $ip = $server.ip
    $name = $server.name
    $hostName = $server.host
    $type = $server.type

# If the device is a guest VM on a cluster or a standalone host:
    if ($type -eq "Guest") { 
        # if hosted on a cluster:
        if ($hostName -in $clusters) {
            Stop-VM –Name $name –ComputerName (Get-ClusterNode –Cluster $hostName) -WarningVariable a
            if ($a -eq $null) { Write-Log -Message "SUCESS, intiating shutdown" } else { Write-Log $a }
        # if hosted on a standalone host:
        } else {
            Stop-VM –Name $name –ComputerName ($hostName) -WarningVariable a
            if ($a -eq $null) { Write-Log -Message "SUCESS, intiating shutdown" } else { Write-Log $a }
        }

# If the device is a physical server:
    } elseif ($type -eq "Host" -or "Physical") {
        shutdown -s -m \\$name -t 1 /f /d p:0:0 /c "Admin Initiated Shutdown"
        # if throws error and is pingable:
        if ($LastExitCode -ne 0 -And (Test-Connection -computername $ip -Quiet -Count 1)) {
            Write-Log -Message "ERROR($LastExitCode)"
        # if throws error and is not pingable:
        } elseif ($LastExitCode -ne 0 -And (!(Test-Connection -computername $ip -Quiet -Count 1))) {
            Write-Log -Message "OFFLINE"
        # no error:
        } else { 
            Write-Log -Message "SUCESS, intiating shutdown"
        }
    }
}
