#######################################################################################
## Description:
##  Check the VMXNET3 multiqueue support
## Revision:
##  v1.0.0 - xinhu - 11/15/2019 - Build the script
#######################################################################################


<#
.Synopsis
    Vertify the VMXNET3 support multiqueue

.Description
    <test>
        <testName>nw_check_vmxnet3_multiqueue</testName>
        <testID>ESX-NW_24</testID>
        <setupScript>setupscripts\change_cpu.ps1</setupScript>
        <testScript>testscripts/nw_check_vmxnet3_multiqueue.ps1</testScript>
        <RevertDefaultSnapshot>True</RevertDefaultSnapshot>
        <timeout>3600</timeout>
        <testParams>
            <param>VCPU=4</param>
            <param>TC_COVERED=RHEL7-50933</param>
        </testParams>
        <onError>Continue</onError>
        <noReboot>False</noReboot> 
    </test>
.Parameter vmName
    Name of the test VM.

.Parameter hvServer
    Name of the VIServer hosting the VM.

.Parameter testParams
    Semicolon separated list of test parameters.
#>


param([String] $vmName, [String] $hvServer, [String] $testParams)


# Checking the input arguments
if (-not $vmName) {
    "FAIL: VM name cannot be null!"
    exit 1
}

if (-not $hvServer) {
    "FAIL: hvServer cannot be null!"
    exit 1
}

if (-not $testParams) {
    Throw "FAIL: No test parameters specified"
}


# Output test parameters so they are captured in log file
"TestParams : '${testParams}'"


# Parse test parameters
$rootDir = $null
$sshKey = $null
$ipv4 = $null
$numCPUs = $null


$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")
    switch ($fields[0].Trim()) {
        "rootDir" { $rootDir = $fields[1].Trim() }
        "sshKey" { $sshKey = $fields[1].Trim() }
        "ipv4" { $ipv4 = $fields[1].Trim() }
        "VCPU" { $numCPUs = [int]$fields[1].Trim() }
        default {}
    }
}


# Check all parameters are valid
if (-not $rootDir) {
    "Warn : no rootdir was specified"
}
else {
    if ( (Test-Path -Path "${rootDir}") ) {
        Set-Location $rootDir
    }
    else {
        "Warn : rootdir '${rootDir}' does not exist"
    }
}

if ($null -eq $sshKey) {
    "FAIL: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4) {
    "FAIL: Test parameter ipv4 was not specified"
    return $False
}

if ($null -eq $numCPUs) {
    "FAIL: Test parameter numCPUs was not specified"
    return $False
}


# Source tcutils.ps1
. .\setupscripts\tcutils.ps1
PowerCLIImport
ConnectToVIServer $env:ENVVISIPADDR `
    $env:ENVVISUSERNAME `
    $env:ENVVISPASSWORD `
    $env:ENVVISPROTOCOL


#######################################################################################
## Main Body
#######################################################################################
$retValdhcp = $Failed
# Define the network queues
$queues = "rx-0","rx-1","rx-2","rx-3","tx-0","tx-1","tx-2","tx-3"


# Function to stop VMB and disconnect with VIserver
Function StopVMB($hvServer,$vmNameB)
{
    $vmObjB = Get-VMHost -Name $hvServer | Get-VM -Name $vmNameB
    Stop-VM -VM $vmObjB -Confirm:$false -RunAsync:$true -ErrorAction SilentlyContinue
    DisconnectWithVIServer
}


# Function to check network queues
Function CheckQueues($sshKey,$ip,$NIC,$queues)
{
    Write-Host -F Green "INFO: Start to check queues of ${ip}"
    Write-Output "INFO: Start to check queues of ${ip}" 
    $result = bin\plink.exe -i ssh\${sshKey} root@${ip} "ls /sys/class/net/$NIC/queues"
    $compare = Compare-Object $result $queues -SyncWindow 0
    if ($compare -ne $null)
    {
        Write-Host -F Red "ERROR: the queues of ${ipv4} is $result , not equal to $queues"
        Write-Output "ERROR: the queues of ${ipv4} is $result , not equal to $queues"
        return $false
    }
    return $true
}


# Function to install netperf on vms
Function InstalNetperf(${sshKey},${ip})
{
    Write-Host -F Green "INFO: Start to install netperf on ${ip}"
    Write-Output "INFO: Start to install netperf on ${ip}"
    # Current have a error "don't have command makeinfo" when install netperf, So cannot judge by echo $?
    $result = bin\plink.exe -i ssh\${sshKey} root@${ip} "yum install -y automake && git clone https://github.com/HewlettPackard/netperf.git && cd netperf && ./autogen.sh && ./configure && make; make install; netperf -h; echo `$?"
    Write-Host -F Red "DEBUG: Log of installing netperf: $result"
    if ( $result[-1] -eq 127)
    {
        Write-Host -F Red "ERROR: Install netperf failed"
        Write-Output "ERROR: Install netperf failed"
        return $false
    }
    return $true
}


# Prepare VMB
$vmOut = Get-VMHost -Name $hvServer | Get-VM -Name $vmName
$vmNameB = $vmName -creplace ("-A$"),"-B"
Write-Host -F Green "INFO: RevertSnap $vmNameB..."
Write-Output "INFO: RevertSnap $vmNameB..."
$result = RevertSnapshotVM $vmNameB $hvServer
if ($result[-1] -ne $true)
{
    Write-Host -F Red "ERROR: RevertSnap $vmNameB failed"
    Write-Output "ERROR: RevertSnap $vmNameB failed"
    DisconnectWithVIServer
    return $Aborted
}

Write-Host -F Red "INFO: set vCpuNum = 4."
$State = Set-VM -VM $vmNameB -NumCpu $numCPUs -Confirm:$false
if (-not $?) {
    Write-Host -F Red "Aborted: Failed to set $vmNameB vCpuNum = 4."
    Write-Output "Aborted: Failed to set $vmNameB vCpuNum = 4."
    DisconnectWithVIServer
    return $Aborted
}

$vmObjB = Get-VMHost -Name $hvServer | Get-VM -Name $vmNameB
Write-Host -F Green "INFO: Starting $vmNameB..."
Write-Output "INFO: Starting $vmNameB..."
Start-VM -VM $vmObjB -Confirm:$false -RunAsync:$true -ErrorAction SilentlyContinue
$ret = WaitForVMSSHReady $vmNameB $hvServer ${sshKey} 300
if ( $ret -ne $true )
{
    write-host -F Red "Failed: Failed to start VM."
    Write-Output "Failed: Failed to start VM."
    DisconnectWithVIServer
    return $Aborted
}
# Refresh status
$vmObjB = Get-VMHost -Name $hvServer | Get-VM -Name $vmNameB
$IPB = GetIPv4ViaPowerCLI $vmNameB $hvServer


# Get NIC name of VMs
$NIC = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "ls /sys/class/net/ | grep ^e[tn][hosp]"
Write-Host -F Green "INFO: Get NIC name $NIC"
Write-Output "INFO: Get NIC name $NIC"


# Check network queues
$CheckA = CheckQueues ${sshKey} ${ipv4} $NIC $queues
if ($CheckA[-1] -ne $true)
{
    Write-Output "ERROR: Check network queues: $CheckA"
    StopVMB $hvServer $vmNameB
    return $Aborted
}
$CheckB = CheckQueues ${sshKey} ${IPB} $NIC $queues
if ($CheckB[-1] -ne $true)
{
    Write-Output "ERROR: Check network queues: $CheckB"
    StopVMB $hvServer $vmNameB
    return $Aborted
}


# Install Netperf on VMs
$IsInsA = InstalNetperf ${sshKey} ${ipv4}
if ($IsInsA[-1] -ne $true)
{
    Write-Output "ERROR: Check network queues: $IsInsA"
    StopVMB $hvServer $vmNameB
    return $Aborted
}
$IsInsB = InstalNetperf ${sshKey} ${IPB}
if ($IsInsB[-1] -ne $true)
{
    Write-Output "ERROR: Check network queues: $IsInsB"
    StopVMB $hvServer $vmNameB
    return $Aborted
}


# Start to netperf from VMB to VMA(as server)
$StarSer = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "netserver;echo `$?"
if ($StarSer[-1] -ne 0)
{
    Write-Host -F Red "ERROR: Make ${ipv4} as netserver Failed: $StarSer"
    Write-Output "ERROR: Make ${ipv4} as netserver Failed;  $StarSer"
    StopVMB $hvServer $vmNameB
    return $Aborted
}
$time=Get-date
Write-Host -F Green "DEBUG: Start to netperf $time"
bin\plink.exe -i ssh\${sshKey} root@${IPB} "netperf -H ${ipv4} -l 2700"
$time=Get-date
Write-Host -F Green "DEBUG: Finish netperf $time"
$Checkqueues = bin\plink.exe -i ssh\${sshKey} root@${ipv4} "cat /proc/interrupts | grep $NIC"
if ($Checkqueues.count -ge 4)
{
    $retValdhcp = $Passed
}
Write-Host -F Green "INFO: $Checkqueues"
Write-Output "INFO: $Checkqueues"

StopVMB $hvServer $vmNameB
return $retValdhcp
