<#
.TITLE
URL Checker

.SYNOPSIS
Checks sites in current subnet using port 80 to determine if they are online

.DESCRIPTION
Checks if IIS sites are up and if they are not, you can optionally receive an email to your inbox, take the webservers out of rotation,
and you can notify the Nimsoft monitoring solution which will notify DCS (Must request approval from SRM-SM prior to using this feature!!!)

.REQUIREMENTS  
Port 80 must be accessible by the system doing the scanning or valid TLS certs must be in use. 
May need to be run from a service account if run as a scheduled task against sites that require authentication. 

.NOTES
Author: Lee Dickey 
Date: 16 MAY 2017
Version: 1.0


	V 1.0 05/16/2017:

		-	First official version. Review each of the configurable sections below
		-	Do not use the Nimsoft alerting feature without first receiving permission from SRM-SM

		#>

#*************************************************************
#*** Configurable Parameters for the main work to be done ****
#*************************************************************

# Script Location to store temporary files to track if email has already been sent. No Trailing slash!
$Path = "c:\allowed\scripts"  	

# List of URLs to check
$URLs = @("", "", "", "")

# Timeout in seconds to wait before failing the request against the website.
$TimeOut = "60"


#*********************************
#*** Email related parameters ****
#*********************************

# Send a direct email to a list of recipients? 
$SendEmail = "no"

# The Outgoing SMTP server
$EmailServer = ""

# Recipients of any alert-emails displaying the system and alert.  Can also be a Distribution Group using fully qualified email address of the DG
$recipients = ""

# Time in minutes before another email is sent. 1440 for a whole 24 hour period. 720 for 12 hours
$EmailFrequency = "120" 	



#***************************************************
# *** Parameters to remove WFE from load balance ***
#***************************************************

# Do you want the WFE to be automatically taken out of load balance?  "yes" if so, otherwise "no"
$RemoveWFE = "yes"

# Name of the Load Balancer config file
[string]$LoadBalancerConfig = "statuspage.htm"

# Physical location of the Load Balancer config file (typically in the inetpub\wwwroot directory in the C drive. W drive if prebuilt PaaS IIS Image)
[string]$IISpath = "w:\inetpub\wwwroot\"


#**********************************************
#*** Customizable NimSoft related variables ***
#**********************************************
# Send Notifications via NimSoft?  (GET PERMISSION FROM SRM-SM prior to using this)
$UseNimsoft = "Yes"

# Unique key for NimSoft to monitor the status of the current alarm so that it can be cancelled or "cleared"
$SessionKey = ""

# NimSoft alert level
$AlertLevel = "2"

# 0 = clear
# 1 = information
# 2 = warning
# 3 = minor
# 4 = major
# 5 = critical




#***************************
# Primary Worker Script ****
#***************************


Foreach ($url in $URLs)
{

Try
    {
    	# Used for my specific system to remove specific parts of the URL so that it can be used in the from address. You 
		# can get rid of this and just use a generic $FromAddress if you want or format it yourself another way        
		$system = $url -replace "http://" -replace "/pwa"

        # Gets the status code from the URLs listed above
        $results = wget -Uri $url -MaximumRedirection 1 -UseDefaultCredentials -DisableKeepAlive -UseBasicParsing -Method Head -TimeoutSec $TimeOut -ErrorAction Stop
        
        # Pulls the status code from the full Results of the wget
        $StatusCode = $Results.Statuscode		
        
        # Feedback if run manually from the console    
        Write-Host "$url Works!"
		
		# Sets a value stating that the wget was successful
        $SuccessCode = "1"
    }

Catch  # Only uses these commands if something is not working.

    {			
		# Some feedback to the console if run manually
		Write-Host "$url is broke!"  
				
		# Puts the error message into a variable to display in the email
		$ErrorMsg = $_.Exception.Message
		
		# Sets value that the wget failed
		$SuccessCode = "0"	
		
		# Delete file(s) after $EmailFrequency minutes 
		Get-childitem $Path | Where-Object { ($_.name -eq "$system") -and ($_.LastWriteTime -le (Get-Date).AddMinutes(-$EmailFrequency)) } | Remove-Item -force -recurse; 
	
			if (!(Test-Path $Path"\$system")) 
				{						
					# The different parts of the email address. FromAddress and Subject can be modified. Recommended the $Body not be modified but up to you
					$FromAddress = "$system@noreply.mil"
					$MessageSubject = "Project Web App (PWA) is down on the following web server: $system."
					$Body = "PWA is down at the following URL: '$url' `n`n`nThe error is as follows: `n$ErrorMsg"  
					
					
					if ($SendEmail -eq "yes")
						{
							# Command to send the actual email
							Send-MailMessage -to $recipients -from $FromAddress -Subject "$MessageSubject" -body $Body -smtpServer $EmailServer -Priority High;
						}
						
						
					# creates timestamp of when the URL failed to load
					$failuretime = Get-Date -f "HH:mm on MM/dd/yyyy";
					
					# Creates a file based on name of failed system to prevent repeat emails as determined in minutes by $EmailFrequency
					new-item -path "$Path" -name "$system" -type "file" -value "$failuretime - Do not delete. Used for URL_Checker script" | out-null
                    
					
                    if ($UseNimsoft -eq "Yes")
                        {
                          # Sends alert to Nimsoft which might generate a DCS call    
                          & "C:\Program Files\Nimsoft\bin\nimalarm.exe" -l $AlertLevel -S $system -c $SessionKey "$MessageSubject $ErrorMsg"					
					    }

						
					if ($RemoveWFE -eq "yes")	
						{
							# Does some work to make the values set above mappable as a UNC path for the statuspage.htm file
							[string]$UNCpath = $IISpath -replace ':','$'
							[string]$F5Location = "\\" + "$system" + "\" + "$UNCpath" + "$LoadBalancerConfig"
							
							# Changes the statuspage.htm value to remove WFE from rotation in load balancer
							(Get-Content -path $F5Location) -replace 'permit_connections=yes','permit_connections=no' | Set-Content $F5Location 
						}
				} 
    }
	
Finally # If a site that was previously down but is now up will generate an "All Clear" type of email
	{
		if ((Test-Path $Path"\$system") -and ($SuccessCode -eq "1"))
			{	
				# Email parameters
				$FromAddress = "$system@noreply.mil"
				$MessageSubject = "Project Web App (PWA) is down on the following web server: $system."
				$Body = "Previously unavailable PWA site at URL: '$url' is back online."  
				
				if ($SendEmail -eq "yes")
					{
						Send-MailMessage -to $recipients -from $FromAddress -Subject "clear - $MessageSubject" -body $Body -smtpServer $EmailServer;
					}
					
					
                # Deletes the file generated when the URL failed to load
				get-childitem $path | where-object { ($_.name -eq "$system") } | remove-item -force -recurse;	

				
                # Clear Nimsoft alert if enabled
                if ($UseNimsoft -eq "Yes")
					{& "C:\Program Files\Nimsoft\bin\nimalarm.exe" -l 0 -S $system -c $SessionKey "$MessageSubject $ErrorMsg"}
											
					
				if ($RemoveWFE -eq "yes")
					{
						# Does some work to make the values set above mappable as a UNC path for the statuspage.htm file
						[string]$UNCpath = $IISpath -replace ':','$'
						[string]$F5Location = "\\" + "$system" + "\" + "$UNCpath" + "$LoadBalancerConfig"
						
						# Adds the WFE back into the load balancer
						(Get-Content $F5Location) -replace 'permit_connections=no','permit_connections=yes' | Set-Content $F5Location 
					}			
			}	
	}		
}
