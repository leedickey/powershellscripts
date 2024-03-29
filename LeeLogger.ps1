####################################
# Logging and Output Function
####################################
<#
Requirements: Log file path set for variable $logfile
Usage:  Generates output for both the console and for a log file
Example: LoggerLee -Text "error message or $ErrorMsg" -Logtype "error"
Author(s): Lee Dickey

#>
function LoggerLee() {   
    [CmdletBinding()]
    param 	(
        [parameter(Mandatory=$True)]  [String]$text,

        [ValidateSet("low","info","warning","error","success")][string]$logType = "info",

        [ValidateSet("newline","nonewline")][string]$linebreak = "newline",

        [string]$logfile = "c:\log_" + (Get-Date -UFormat %Y-%m-%d) + ".log"
			)

    Switch ($logType)
    {
        "warning" {
            $color = "yellow";
            $bgcolor = "black";
				  }
        "error" {
            $color = "red";
            $bgcolor = "black";
				}
        "info" 	{
            $color = "white";
            $bgcolor = "blue";
				}
		"success" 	{		
			$color = "Green";
            $bgcolor = "DarkBlue";
					}
		"low"		{
			$color = "DarkGray";
			$bgcolor = "Darkblue";
					}
    }
    Switch ($linebreak)
    {
        "nonewline" {
            $nobreak = "-NoNewLine";            
                    }
        "newline" {
            $nobreak = "";    
                    }    
  }       
	
    $LogTime = get-date -Format g
    #$logfile = "c:\allowed\scripts\AAATestingSTuff.log"
        
	if ($logtype -eq "low")
	{	write-host "$Text" -ForegroundColor $color -nonewline
		if ($linebreak -eq "newline") {write-host ""}	}
	
	else
	{	Write-Output "`n >> $LogTime - $Text" | out-file $logfile -Append;
		write-host "$Text" -ForegroundColor $color -BackgroundColor $bgcolor -nonewline
		if ($linebreak -eq "newline") {write-host ""} }        
}  
