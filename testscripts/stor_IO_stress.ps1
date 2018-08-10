###############################################################################
##
## Description:
##  Test the guest with IO stress tool.
##
## Revision:
##  v1.0.0 - ldu - 08/06/2018 - Build the script
##
###############################################################################

<#
.Synopsis
    Test the guest with IO stress tool iozone.

.Description


.Parameter vmName
    Name of the test VM.

.Parameter testParams
    Semicolon separated list of test parameters.
#>


param([String] $vmName, [String] $hvServer, [String] $testParams)


#
# Checking the input arguments
#
if (-not $vmName) {
    "Error: VM name cannot be null!"
    exit 100
}

if (-not $hvServer) {
    "Error: hvServer cannot be null!"
    exit 100
}

if (-not $testParams) {
    Throw "Error: No test parameters specified"
}


#
# Output test parameters so they are captured in log file
#
"TestParams : '${testParams}'"


#
# Parse the test parameters
#
$rootDir = $null
$sshKey = $null
$ipv4 = $null

$params = $testParams.Split(";")
foreach ($p in $params) {
    $fields = $p.Split("=")
    switch ($fields[0].Trim()) {
        "sshKey" { $sshKey = $fields[1].Trim() }
        "rootDir" { $rootDir = $fields[1].Trim() }
        "ipv4" { $ipv4 = $fields[1].Trim() }
        default {}
    }
}


#
# Check all parameters are valid
#
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


#
# Source the tcutils.ps1 file
#
. .\setupscripts\tcutils.ps1

PowerCLIImport
ConnectToVIServer $env:ENVVISIPADDR `
    $env:ENVVISUSERNAME `
    $env:ENVVISPASSWORD `
    $env:ENVVISPROTOCOL


###############################################################################
#
# Main Body
#
###############################################################################


$retVal = $Failed

$vmObj = Get-VMHost -Name $hvServer | Get-VM -Name $vmName
if (-not $vmObj) {
    LogPrint "ERROR: Unable to Get-VM with $vmName"
    DisconnectWithVIServer
    return $Aborted
}

#Run remote scripts to install iozone and run iozone test.
$scripts = "stor_iozone_stress.sh"
# Run remote test scripts
$sts =  RunRemoteScript $scripts
if( -not $sts[-1] )
{
    Write-Host -F Red "ERROR:iozone  run failed"
    Write-Output "ERROR: iozone run failed"
    return $Aborted
}
else
{
    Write-Host -F Red "Info :iozone run successfully"
    Write-Output "Info : iozone run successfully"
}

# check system dmesg
$command = "dmesg | grep -i `"call trace`" | wc -l"
$error_num = [int] (bin\plink.exe -i ssh\${sshkey} root@${ipv4} $command)
if ($error_num -ne 0)
{
    LogPrint "error : iozone stress test has error call trace in $vmname"
    disconnectwithviserver
    return $Failed
}
else
{
    $retVal = $Passed
}

DisconnectWithVIServer
return $retVal
