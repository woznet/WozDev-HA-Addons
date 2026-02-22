# Set up some stuff we only need to do once.
# Set the culture to British English, since I'm British.
#$CultureInfo = [cultureinfo]::new('en-US')
#[System.Threading.Thread]::CurrentThread.CurrentCulture = $CultureInfo
#[System.Threading.Thread]::CurrentThread.CurrentUICulture = $CultureInfo

function Write-ColoredBlock {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Style
    )

    foreach ($Line in ($Text -split '\r?\n')) {
        if ($Line -ne '') {
            Write-Output ('{0}{1}{2}' -f $Style, $Line, $PSStyle.Reset)
        }
        else {
            Write-Output ''
        }
    }
}

# Path to options.json file - this is the file that's placed/mapped/linked in to the running container.
$OPTIONS_FILE = '/data/options.json'

# Read and convert the JSON file to a PowerShell object - we'll use these to get data from the user for use later.
$OPTIONS = Get-Content $OPTIONS_FILE | ConvertFrom-Json -ErrorAction Stop

# Throttle Limit defines the number of scripts that will be started as threads by *this* script.
# Bear in mind that if the `Scripts` list's first n scripts run as infinite loops, any scripts over
# the Throttle Limit will never start (and will spam the logs too). So you'll either need to increase
# the Throttle Limit, or have the other scripts start (and complete) before your infinite looping scripts.
$ThreadThrottleLimit = [int]$OPTIONS.threads

# Colors for banner information during startup etc.
$Green = $PSStyle.Foreground.Green
$BlackBg = $PSStyle.Background.Black
$Red = $PSStyle.Foreground.Red
$Reset = $PSStyle.Reset

# We still want to limit the number of scripts.
if ($OPTIONS.scripts.length -gt 10) {
    throw 'Scripts are limited to a maximum of 10 at a single time.'
}

# /mnt/data/supervisor/addons/data/local_pwsh is mapped from the host to the container as /data and where options.json lives.
# We want the share folder to map to the container so the user places their scripts there.
$DefaultScriptLocation = '/share/pwsh/'
if (!(Test-Path $DefaultScriptLocation)) {
    $FolderBanner = @'
#####################################
## Creating /share/pwsh folder...  ##
#####################################

########################################################
## Since the folder has just been created, the add-on ##
## will stop now. Add your scripts and configure the  ##
## add-on now.                                        ##
########################################################
'@
    Write-ColoredBlock -Text $FolderBanner -Style $Green

    $null = New-Item -Path $DefaultScriptLocation -ItemType Directory
    exit 0
}

# Warn the user that on-demand is enabled.
$OnDemand = $OPTIONS.ondemand
if ($OnDemand) {
    $OnDemandBanner = @'
###############################################
##      ! ON-DEMAND MODE ENABLED !           ##
##                                           ##
##   When enabled, a thread job is created   ##
##   to stop the add-on from exiting after   ##
##   Declared scripts complete.              ##
##                                           ##
## Use hassio.addon_stdin to send filenames. ##
## Please review the README for more detail. ##
###############################################
'@
    Write-ColoredBlock -Text $OnDemandBanner -Style $Red

    $null = Start-ThreadJob -ScriptBlock {while ($true) {Start-Sleep -Seconds 3600}} -Name 'On-Demand-Listener' -ErrorAction Stop -ThrottleLimit $ThreadThrottleLimit
    Start-Process nohup 'pwsh -NoProfile -NoLogo -File /app/Read-HassIoStdIn.ps1'
}

# Doing this forces the user to know and set what scripts will run. Just banging them in a folder ain't good.
$Scripts = $OPTIONS.scripts

# A way to understand what log is associated with what script.
$JobColors = @{}
$RandomisedColors = $PSStyle.Background.PSObject.Properties.Name | Where-Object { $_ -notmatch 'Bright' } | Sort-Object { Get-Random }
$i = 0

$ScriptCount = $Scripts.Count

if ($ScriptCount -gt 0) {
    $StartupBanner = @'
###########################
## DECLARED SCRIPTS MODE ##
##                       ##
##    Starting up...     ##
##                       ##
##   PowerShell {0}    ##
##   ThrottleLimit: {1}    ##
##   {2}    ##
###########################
'@ -f $PSVersionTable.PSVersion.ToString(), $ThreadThrottleLimit, (Get-Date -UFormat '%Y-%m-%d %H:%M')
    Write-ColoredBlock -Text $StartupBanner -Style $Green
}

if (($ScriptCount -eq 0) -and ($null -eq $OnDemand)) {
    $NoScriptsBanner = @'
######################################
## No scripts were found in the     ##
## Configuration -> Scripts section ##
## of the add-on and On-Demand Mode ##
## is not enabled either. 🤦        ##
## Nothing else to do. Bye.         ##
######################################
'@
    Write-ColoredBlock -Text $NoScriptsBanner -Style $Green
    exit 0
}

# Loop through each script and start a thread job for each one
foreach ($Script in $Scripts) {

    if ($null -eq $Script.path) { $ScriptLocation = $DefaultScriptLocation }
    else { $ScriptLocation = $Script.path }

    $ScriptFullPath = Join-Path $ScriptLocation $Script.filename

    $ValidPath = Test-Path -Path $ScriptFullPath -PathType Leaf

    if ($ValidPath) {
        $ThisScript = Get-Item -Path $ScriptFullPath
        $ScriptArgs = @()
        if ($null -ne $Script.args) {
            if ($Script.args -is [array]) {
                $ScriptArgs = @($Script.args | ForEach-Object { [string]$_ })
            }
            else {
                $ScriptArgs = @([string]$Script.args)
            }
        }

        $ThreadJobParams = @{
            FilePath = $ThisScript.FullName
            Name = $ThisScript.BaseName
            StreamingHost = $Host
            ErrorAction = 'Continue'
            ThrottleLimit = $ThreadThrottleLimit
        }

        if ($ScriptArgs.Count -gt 0) {
            $ThreadJobParams.ArgumentList = $ScriptArgs
        }

        try {
            $Job = Start-ThreadJob @ThreadJobParams

            $RandomColor = $RandomisedColors[$i]
            $JobColors[$Job.Name] = $RandomColor  # Store the job name and its associated Color
            Write-ColoredBlock -Text ('{0} created.' -f $Job.Name) -Style ($PSStyle.Background.$RandomColor)
            $i++
            if ($i -eq 8) { $i = 0 }
        }
        catch {
            Write-ColoredBlock -Text ('Unable to start the thread for: {0}{1}' -f $ScriptLocation, $Script.filename) -Style $PSStyle.Foreground.Red
            $i++
            if ($i -eq 8) { $i = 0 }
        }
    }
    else {
        Write-ColoredBlock -Text ('Unable to find path: {0}{1}' -f $ScriptLocation, $Script.filename) -Style $PSStyle.Foreground.Red
    }
}

$JobCount = (Get-Job).Count

if ($JobCount -eq 0) {
    $NoJobsBanner = @'
#############################################
## No thread jobs were added and On-Demand ##
## Mode is not enabled/running. Did you    ##
## forget to add your scripts in the       ##
## right place?                            ##
## Nothing else to do. Bye.                ##
#############################################
'@ -f $Green, $Reset
    Write-ColoredBlock -Text $NoJobsBanner -Style $Green
    exit 0
}
else {
    $JobsRunningBanner = @'
########################################
## On-Demand Mode / Declared scripts  ##
## running...                         ##
##                                    ##
## ThrottleLimit: {0}                   ##
## {1}                   ##
########################################
'@ -f $ThreadThrottleLimit, (Get-Date -UFormat '%Y-%m-%d %H:%M')
    Write-ColoredBlock -Text $JobsRunningBanner -Style $Green

    # Deals with the case where we receive multiple lines or a single line of output from Receive-Job.
    function Out-JobData {
        param (
            [Parameter(Mandatory)]
            $Data,

            [Parameter(Mandatory)]
            [string]$JobName,

            [Parameter(Mandatory)]
            [string]$JobColor
        )
        if ($Data -is [array]) {
            for ($i = 0; $i -lt $Data.Count; $i++) {
                Write-ColoredBlock -Text ('{0}: {1}' -f $JobName, $Data[$i]) -Style ($PSStyle.Background.$JobColor)
            }
        }
        else {
            Write-ColoredBlock -Text ('{0}: {1}' -f $JobName, $Data) -Style ($PSStyle.Background.$JobColor)
        }
    }
}

while ($Jobs = Get-Job) {
    foreach ($Job in $Jobs) {

        # No point processing anything if it's the On-Demand-Listener job.
        if ($Job.Name -eq 'On-Demand-Listener') { continue }

        $JobColor = $JobColors[$Job.Name]
        switch ($Job.State) {
            { ($_ -eq 'Completed') -or ($_ -eq 'Stopped') -or ($_ -eq 'Failed') } {
                if ($Job.HasMoreData) {
                    $Data = Receive-Job -Job $Job
                    Out-JobData -Data $Data -JobName $Job.Name -JobColor $JobColor
                }
                else {
                    Write-ColoredBlock -Text ('{0}: Done. Removing this {1} job.' -f $Job.Name, $Job.State.ToUpper()) -Style ($PSStyle.Background.$JobColor)
                    $null = Remove-Job -Job $Job
                }
            }
            'Running' {
                if ($Job.HasMoreData) {
                    $Data = Receive-Job -Job $Job
                    Out-JobData -Data $Data -JobName $Job.Name -JobColor $JobColor
                }

            }
            'NotStarted' {
                Write-ColoredBlock -Text ('{0}: This job has not started yet, waiting for a job slot (Throttle Limit!)...' -f $Job.Name) -Style ($PSStyle.Background.$JobColor)
                continue
            }
            default {
                if ($Job.HasMoreData) {
                    $Data = Receive-Job -Job $Job
                    Out-JobData -Data $Data -JobName $Job.Name -JobColor $JobColor
                }
                else {
                    Write-ColoredBlock -Text ('{0}: Stopping this {1} job.' -f $Job.Name, $Job.State.ToUpper()) -Style ($PSStyle.Background.$JobColor)
                    $null = Stop-Job -Job $Job
                }
            }
        }
    }
    Start-Sleep -Seconds 10
}

$CompleteBanner = @'
#######################
##  HASS PowerShell  ##
## All jobs complete ##
## {0}  ##
#######################
'@ -f (Get-Date -UFormat '%Y-%m-%d %H:%M')
Write-ColoredBlock -Text $CompleteBanner -Style $Green
