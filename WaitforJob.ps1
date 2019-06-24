#######################################################
# PowerShell Jobs  - Wait to be completed  
#######################################################

# Waits for the PowerShell job on the server to reach the required state.
function WaitForJob([string]$jobName, [string]$jobState)
{
	LoggerLee -text "`n`nWaiting for a background job to be $jobState" low nonewline

	do
	{
		Start-Sleep 1
		Write-Host -foregroundcolor DarkGray -NoNewline "."
        $jobstatus = get-job -name $jobName 
	}
        
	while ($jobstatus.State -ne $jobState)
    Write-Host " "
    Write-Host " "

	#Write-Host -foregroundcolor DarkGray -NoNewLine " The job $jobName is "
	#Write-Host -foregroundcolor Gray $jobState
	
    #LoggerLee " The background job is " low nonewline
	#LoggerLee "$jobState`n" low
}
