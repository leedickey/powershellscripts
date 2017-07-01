<#  ServiceChecker 
	- This script checks if a Windows service is not running and starts it if it isn't disabled. 
	- Optional email notifications if a service is disabled or doesn't start-up if enabled.
	- To do: Add additional check if a started service actually started and if not, notify the recipient via email if desired - DONE
	- To do: Convert Email option into a function and clean up duplicated commands

Created By: by Lee Dickey.  
Tested on 2008 R2 and 2012 R2

*** HOW TO CREATE SCHEDULED TASK ***
Put script in c:\Allowed\Scripts with a .ps1 extension
Modify the below two sections for which services to monitor and whether or not you want to receive email notifications
Create a scheduled task:  
	- "Create Task" option
General Tab: 
	- Run with Highest privileges
	- Change User or Group to "System" (Should show as NT AUTHORITY\SYSTEM on General tab after clicking OK)
	- Run whether user is logged on or not checked
	- Configure For: Windows Server 2012 R2 (or your version of Windows)

Triggers tab: 
	- Create your schedule of when to start. 
	- Repeat every 5 minutes (Can change this by typing into the box. Not limited to drop-down options)

Action tab: NEW
	- Program / script: Powershell
	- Add arguments (optional): -executionpolicy bypass -file "C:\Allowed\Scripts\servicescheck.ps1"
	#>
	
	
#    ***NOTICE:  MUST RUN AS ADMINISTRATOR TO WORK PROPERLY***	
	
#################################################################		
#
#	Add the services you wish for this script to monitor. They
#	are separated by commas	with each service enclosed in
#	double-quotes. Unless you wish to receive emails when
#	the services are disabled, this is the only part of the
# 	script that requires modification.
#
#################################################################

#==============================================================
# ADD SERVICES TO BE MONITORED HERE
#==============================================================

# --Place service names in the quotes separated by commas if more than one.--
$ServiceList = @("", "") 


##############################################################	
#
#	This section is only used if you want emails sent to you	
#	if a service that you wish to have monitored is set to
#	disabled and cannot be started. You can ignore the below
#	settings otherwise.
#
##############################################################

#----- Generates a transcript log each time this script runs if enabled with "yes" -----#
$EnableLogging = "no"

# --'yes' if you want to receive notification email. Should only be used if scheduled task--
$SendAlertEmail = "yes" 						

# --Your SMTP server for sending emails--
$EmailServer = "" 							

# --add multiple recipients by separating after quotes with a comma--
$recipients = ""

# -- The from address in the notification emails. You do not need to change this. --
$FromAddress = "$env:ComputerName@noreply.com"; 

# --Location to store temporary files to track if email has already been sent. No Trailing slash!--
$Path = "c:\allowed\scripts"  		

# --Time in minutes before another email is sent. 1440 for a whole 24 hour period--
$Frequency = "720" 			
				
# Logging if enabled above
if($EnableLogging -eq "yes") {Start-Transcript -Path c:\allowed\scripts\Log_Report_transcript.txt -Append}


#################################################################		
#
#	This section does all of the work and should not
#	require any changes or any manipulation.
#
#################################################################

clear-host
foreach ($service in $ServiceList) {
$failuretime = Get-Date -f "HH:mm on MM/dd/yyyy"; # creates timestamp of when the service failed to start and is placed in the email body
$ServiceState = Get-Service -Name $service

Write-Host "`n `n `n*******************************************"
Write-Host "Starting actions on $service"
Write-host "*******************************************"

if (($ServiceState.StartType -eq "Disabled") -and ($ServiceState.Status -eq "Stopped")) #Checks if service being monitored is disabled and stopped 
	{		
			if ($SendAlertEmail -eq "yes")	# If emails are desired, they will be sent sent. No need to edit anything here unless alternative email text is desired *Discouraged*
			{
				Get-childitem $Path | Where-Object { ($_.name -eq "$service") -and ($_.LastWriteTime -le (Get-Date).AddMinutes(-$Frequency)) } | Remove-Item -force -recurse; # Delete file(s) after $Frequency minutes 
				
	
					if (!(Test-Path $Path"\$service")) # If the file with name of $service doesn't exist, the email will be sent.
						{
						Write-Host "`nThe service $service is disabled on $env:ComputerName and email alerts are requested";
						Write-Host "	`nSending email for disabled service: $service"
						$MessageSubject = "Service $service Failed to start on $env:ComputerName";
						$Body += "$service is Disabled and failed to start on $env:ComputerName at $failuretime";
						$Body += "`n `nCheck and make sure the $service service is set to automatic on $env:ComputerName";
						Send-MailMessage -to $recipients -from $FromAddress -Subject "ALERT! - $MessageSubject" -body $Body -smtpServer $EmailServer;
						$Body = ""	# Overwrites string being used as email body so additional service emails are not combined
						Write-Host "`nAlert email for disabled $service sent to $Recipients";
						
						new-item -path "$Path" -name "$service" -type "file" -value "$failuretime - Do not delete. Used for ServiceChecker script" | out-null; # Creates a file based on name of service to prevent repeat emails as determined in minutes by $frequency
						}
					
					else	
						{
						Write-Host "$service is disabled and the notification Email has already been sent."
						}			
			}			
					
			else
				{Write-Host "`n ----No email requested for disabled service: $service"}
				
	} 


# If the service is not running and is set to Manual or Automatic.....
if (($ServiceState.Status -eq "Stopped") -and ($ServiceState.StartType -ne "disabled")) 	

	{
		(Start-Service $service -ErrorAction SilentlyContinue); # Starts the service. 
		 Start-Sleep -s 5;	#Waits 5 seconds to give the service time to fully start.
		 $ServiceState = Get-Service -Name $service
		 
			if (($ServiceState.Status -eq "Stopped") -and ($SendAlertEmail -eq "yes")) # Checks if the service successfully started and sends an email if not
			{	Get-childitem $Path | Where-Object { ($_.name -eq "$service") -and ($_.LastWriteTime -le (Get-Date).AddMinutes(-$Frequency)) } | Remove-Item -force -recurse; # Delete file(s) after $Frequency minutes
				
				
						if (!(Test-Path $Path"\$service"))
							{						
								Write-Host "`nThe $service service did not start. Sending Notification email"
								$MessageSubject = "Service $service Failed to start on $env:ComputerName";
								$Body = "Attempted to start $service on $env:ComputerName but it did not start. Please check the system for problems.";
								Send-MailMessage -to $recipients -from $FromAddress -Subject "Notice! - $MessageSubject" -body $Body -smtpServer $EmailServer;
								new-item -path "$Path" -name "$service" -type "file" -value "$failuretime - Do not delete. Used for ServiceChecker script" | out-null; # Creates a file based on name of service to prevent repeat emails as determined in minutes by $frequency

							}		
						
						else { Write-Host "$service is failing to start and the notification email has already been sent."}											
			}
			
			else 
			{
				Write-Host "`n$service started on $env:ComputerName;" 
					# Sends an email if the service is started and if email notification is enabled
					if (($SendAlertEmail -eq "yes") -and ($servicestate.status -eq "running")) {
						$MessageSubject = "Service $service was successfully started on $env:ComputerName";
						$Body = "The service $service on $env:ComputerName was not running and had to be started.";
						Send-MailMessage -to $recipients -from $FromAddress -Subject "Information - $MessageSubject" -body $Body -smtpServer $EmailServer;
						Write-Host "`nEmail sent notifying $Recipients of the service restart"}
						
							If (test-path $path"\$service")
								{get-childitem $path | where-object { ($_.name -eq "$service") } | remove-item -force -recurse;}						
			}			
	}
	
else
		{ Write-Host " -$service is already running (or is not enabled)" }	

# Checks for a service that previously failed to start but is now able to start - sends an email and removes the file
if (($servicestate.status -eq "running") -and (test-path $path"\$service") -and ($sendalertemail -eq "yes"))
		{
			write-host "`n$service was previously unable to start but is now running as of $failuretime.";
			$messagesubject = "previous failed $service has now started on $env:computername";
			$body = "The service $service on $env:computername had previously failed to start but it has now started successfully at $failuretime.";
			send-mailmessage -to $recipients -from $fromaddress -subject "Good News! - $messagesubject" -body $body -smtpserver $emailserver;
			get-childitem $path | where-object { ($_.name -eq "$service") } | remove-item -force -recurse;
		}
Write-Host "`n `n"			 
 }

# Required stopping of the transcript if enabled above
if($EnableLogging -eq "yes") {Stop-Transcript}	