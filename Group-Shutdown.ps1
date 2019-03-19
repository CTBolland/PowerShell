#REQUIRES -Version 2.0
<# 
.SYNOPSIS
    Group Shutdown of Remote Computers
.DESCRIPTION
    Pulls from a CSV list and shutsdown servers. If its a vm, it sends a "Stop-VM" command to the host.
    If it's a physical box, it sends a "\\Shutdown command". This command requires that the physical 
    server is configured to allow remote shutdown. This script is best used in conjunction with task 
    scheduler, or paired with a power management solution such as Eaton. 
.INPUTS
    This CSV that contains all the device information should have the following columns:
        name --- Device name
        ip ----- IP address of device
        type --- Host or Guest
        host --- If type is guest, then host name goes here
        group -- Assign device to a group. These groups are used to target collections of devices

    Example CSV:

    name        ip              type    host        group
    ---------------------------------------------------
    Server01    192.168.0.8     host                B
    vm01        192.168.0.9     guest   Server01    A   
    vm02        192.168.0.19    guest   Server01    A

.PARAMETER group
    Target specifc groups within the csv  

.PARAMETER list
    Path to the CSV device list

.EXAMPLE
    Shutdown group A, which is comprised of the guests running on Server01:
        .\Group-Shutdown.ps1 -list "C:\Temp\servers.csv" -group "A"

    Shutdown group B, which is the host:
        .\Group-Shutdown.ps1 -list "C:\Temp\servers.csv" -group "B"

.NOTES       
    AUTHOR:         Craig Bolland
    CREATED:        02-26-2019 
    UPDATED:        03-19-2019 
#> 
# ---------------------------------------------------------- 

param (
    [string]$list,
    [string]$group
    )  

# logging variables and function
$log = "C:\Scripts\Eaton\Server\Logs\" + (Get-Date).tostring("MM-dd-yyyy") + "-Server Shutdown.log" 
if(!(Test-Path -Path $log )){New-Item -ItemType File -Path $log}
function Write-Log {
    param (
        [string]$Message
    )  
    $time = "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
    Write-Output "$($time)Group[$group]-[$ip]-[$name]-[$hoster] $message"| Out-file $log  -Append -Force
}
# select all devices in the specified group
$servers = Import-Csv -Path $list| Where-Object {$_.Group -eq $group} 
foreach ($server in $servers) {
    # csv variables
    $ip = $server.ip
    $name = $server.name
    $hoster = $server.host
    $type = $server.type
    # determine if VM
    if ($type -eq "Guest") { 
        $s = New-PSSession -ComputerName $hoster
        Invoke-Command -Session $s -ScriptBlock {param($vm) Stop-VM $vm -Force} -ArgumentList $name -WarningVariable a
        Write-Log $a
        $r = Get-PSSession -ComputerName $hoster
        $r | Remove-PSSession
    # determine if physical box
    } elseif ($type -eq "Host" -or "Physical") {
        shutdown -s -m \\$name -t 1 /f /d p:0:0 /c "Eaton Power Manager Shutdown"
        # the sever will either shutdown or return an error. If an error, it's either
        # because its offline or not configured for remote shutdown. This determines which.
        if ($LastExitCode -ne 0 -And (Test-Connection -computername $ip -Quiet -Count 1)) {
            Write-Log -Message "ERROR($LastExitCode)"
        } elseif ($LastExitCode -ne 0 -And (!(Test-Connection -computername $ip -Quiet -Count 1))) {
            Write-Log -Message "OFFLINE"
        } else {
            Write-Log -Message "SUCESS, intiating shutdown"
        }
    }
}
