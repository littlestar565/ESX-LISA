########################################################################################
## Description:
##  Add RDM disk to guest and boot check status.
##
## Revision:
##  v1.0.0 - ldu - 09/20/2019 - Build the script
########################################################################################


<#
.Synopsis
    Add RDM disk to guest and boot check status.

.Description
        <test>
        <testName>stor_add_RDM_disk</testName>
        <setupScript>SetupScripts\add_hard_disk.ps1</setupScript>
        <testID>ESX-Stor-021</testID>
        <testScript>testscripts\stor_add_RDM_disk.ps1</testScript>
        <files>
                remote-scripts/utils.sh,remote-scripts/stor_add_disk_ide.sh
        </files>
        <!-- <cleanupScript>SetupScripts\remove_hard_disk.ps1</cleanupScript> -->
        <testParams>
            <param>DiskType=RawPhysical</param>
            <param>TC_COVERED=RHEL-111401</param>
        </testParams>
        <RevertDefaultSnapshot>True</RevertDefaultSnapshot>
        <timeout>900</timeout>
        <onError>Continue</onError>
        <noReboot>False</noReboot>
    </test>

.Parameter vmName
    Name of the test VM.

.Parameter testParams
    Semicolon separated list of test parameters.
#>


param([String] $vmName, [String] $hvServer, [String] $testParams)



# Checking the input arguments
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


# Output test parameters so they are captured in log file
"TestParams : '${testParams}'"


# Parse the test parameters
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


# Source the tcutils.ps1 file
. .\setupscripts\tcutils.ps1

PowerCLIImport
ConnectToVIServer $env:ENVVISIPADDR `
    $env:ENVVISUSERNAME `
    $env:ENVVISPASSWORD `
    $env:ENVVISPROTOCOL


########################################################################################
# Main Body
########################################################################################


$retVal = $Failed


$vmObj = Get-VMHost -Name $hvServer | Get-VM -Name $vmName
if (-not $vmObj) {
    Write-Host -F Red "ERROR: Unable to Get-VM with $vmName"
    Write-Output "ERROR: Unable to Get-VM with $vmName"
    DisconnectWithVIServer
    return $Aborted
}


# Get the Guest version
$DISTRO = GetLinuxDistro ${ipv4} ${sshKey}
Write-Host -F Red "DEBUG: DISTRO: $DISTRO"
Write-Output "DEBUG: DISTRO: $DISTRO"
if (-not $DISTRO) {
    Write-Host -F Red "ERROR: Guest OS version is NULL"
    Write-Output "ERROR: Guest OS version is NULL"
    DisconnectWithVIServer
    return $Aborted
} else{
    Write-Host -F Red "INFO: Guest OS version is $DISTRO"
    Write-Output "INFO: Guest OS version is $DISTRO"
}



# Different Guest DISTRO, different modules
if ($DISTRO -ne "RedHat7" -and $DISTRO -ne "RedHat8" -and $DISTRO -ne "RedHat6") {
    Write-Host -F Red "ERROR: Guest OS ($DISTRO) isn't supported, MUST UPDATE in Framework / XML / Script"
    Write-Output "ERROR: Guest OS ($DISTRO) isn't supported, MUST UPDATE in Framework / XML / Script"
    DisconnectWithVIServer
    return $Skipped
}


$scripts = "stor_add_disk_ide.sh"
# Run remote test scripts
RunRemoteScript $scripts | Write-Output -OutVariable sts
if( -not $sts[-1] ){
    Write-Host -F Red "ERROR: Add RDM disk test script  failed"
    Write-Output "ERROR: Add RDM disk test script failed"
}  else {
    Write-Host -F Red "Info : Add RDM disk test script completed"
    Write-Output "Info : Add RDM disk test script completed"
    $retVal = $Passed
}


DisconnectWithVIServer
return $retVal
