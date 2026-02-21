# Create a native command-line argument string suitable for Start-Process.
# Start-Process joins string[] with spaces and can split values like "hello world"
# unless tokens that require it are quoted/escaped explicitly.
function Join-StartProcessArgs {
    param(
        [Parameter(Mandatory)]
        [string[]]$Tokens
    )

    $EscapedTokens = foreach ($Token in $Tokens) {
        if ($null -eq $Token) {
            '""'
            continue
        }

        $Text = [string]$Token
        $EscapedText = $Text -replace '`', '``' -replace '"', '`"'

        if ($EscapedText -match '[\s"`]') {
            '"{0}"' -f $EscapedText
        }
        else {
            $EscapedText
        }
    }

    $EscapedTokens -join ' '
}

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


# Now wait for on-demand script starts.
while ($true) {
    $FromHassIo = Read-Host

    $InputJSON = $FromHassIo | ConvertFrom-Json -ErrorAction Continue
    $Scripts = $InputJSON.scripts

    $RedFg = $PSStyle.Foreground.Red
    $BlackBg = $PSStyle.Background.Black
    $BlueFg = $PSStyle.Foreground.Blue
    $Reset = $PSStyle.Reset

    if (-not $Scripts) {
        $ErrorBanner = @'
###############################################
#             ! ON-DEMAND ERROR !             #
# The supplied "scripts" value is empty!      #
# Ensure you're sending a properly formatted  #
# list! eg.                                   #
# action: hassio.addon_stdin                  #
# data:                                       #
#   addon: {0}                      #
#   input:                                    #
#     scripts:                                #
#       - filename: On-Demand.ps1             #
###############################################
'@ -f ($env:HOSTNAME -replace ('-', '_'))
        Write-ColoredBlock -Text $ErrorBanner -Style ($BlackBg + $RedFg)
        continue
    }

    $DefaultScriptPath = '/share/pwsh/'

    foreach ($Script in $Scripts) {
        $ScriptPath = if ($Script.path) { $Script.path } else { $DefaultScriptPath }
        $FullScriptPath = Join-Path $ScriptPath $Script.filename
        $ScriptArgs = @()

        if ($null -ne $Script.args) {
            if ($Script.args -is [array]) {
                $ScriptArgs = @($Script.args | ForEach-Object { [string]$_ })
            }
            else {
                $ScriptArgs = @([string]$Script.args)
            }
        }

        if (Test-Path $FullScriptPath) {
            try {
                $OnDemandStyle = $BlackBg + $RedFg
                $AttemptMessage = 'ON-DEMAND: Attempting to run {0}{1}{2}...' -f $BlueFg, $FullScriptPath, $OnDemandStyle
                Write-ColoredBlock -Text $AttemptMessage -Style $OnDemandStyle
                $ProcessArguments = @('-File', $FullScriptPath)
                if ($ScriptArgs.Count -gt 0) {
                    $ProcessArguments += $ScriptArgs
                }

                $ProcessArgumentString = Join-StartProcessArgs -Tokens $ProcessArguments
                Start-Process -FilePath 'pwsh' -ArgumentList $ProcessArgumentString
            }
            catch {
                Write-Error ('Error executing script: {0}' -f $_) -ErrorAction Continue
            }
        }
        else {
            $OnDemandStyle = $BlackBg + $RedFg
            $NotFoundMessage = @'
ON-DEMAND ERROR: File {0}{1}{2} not found.
File names and paths are cAsE-sEnsiTive.
'@ -f $BlueFg, $FullScriptPath, $OnDemandStyle
            Write-ColoredBlock -Text $NotFoundMessage -Style $OnDemandStyle
        }
    }
    Start-Sleep -Seconds 1
}
