<#
.SYNOPSIS
Performs multiple tasks for the SharePoint Farm via a menu.
.DESCRIPTION
Changes account passwords using the provided CSV (inputfile), restarts the farm and other tasks.
.EXAMPLE
.\SharePoint2016Tasks.ps1 

.NOTES
Author: Lee Dickey 
Date: 26 June 2019
Version: 3.1

V 3.1 06/26/2019
		- Fixed a bug with one function not working due to a -WhatIf left behind after development (whoops!)
		- Minor text fixes for easier log reading
		- Fixed bug with the log not getting created and encrypted on first run of the script 

V 3.0 06/24/2019 -COMPLETE REWRITE-		
		- Added logging function to both capture a log and display to the host (LoggerLee)
			- Log file is created at first run of the script and is immediately encrypted
		- Rewrote all of the functions requiring the invoke-command to properly make future troubleshooting easier
			- Most all of the functions now use a template (for the most part) that makes modification easier if required
		- Corrected error handling actions (stop instead of continue)
		- Rewrote Job handling so it makes more sense
		- Added a function to change passswords on existing Scheduled Tasks (needs additional testing)
		- Fixed a number of bugs that cropped up over the past year.

	UNTESTED:
		- Added encrypting and decrypting of the $logfile to the menu and actions, HOWEVER, the log file changes from run-to-run. Would be best
		  to delete the log files once completed to prevent leakage of credential data.

V 2.2 05/07/2018
		- Added commands to encrypt and decrypt the Accounts.csv file.
			* Only the user that encrypted the file can read and decrypt it.
		- Add new commands to list the App Pools and Windows services that will be affected by the scripts other commands
		- Added more details to the .Requirements for firewall permissions, WinRM activation, and PowerShell features
		- Removed outdated and no longer used functions 

V 2.1 06/13/2017
	- Added new function to restart running Windows Services specific to SharePoint
	- Added new function to recycle AppPools specific to the SharePoint farm
	- Added secondary sub-menu for post-password change troubleshooting tasks (some are dupes)
	- Cleaned up font coloring and text formatting

V 2.0 05/24/2017
	- Enabled parrallel processing of tasks to multiple functions to speed up tasks using PowerShell jobs.
	- Minor text fixes

V 1.2 04/25/2017
	-	Completely rewrote the menu system which improves functionality in a significant way and shortens the code to 1/3 original length.
	-	Minor text and formatting fixes

V 1.1 04/20/2017 
	-	Corrected output formatting issues with function to start App Pools
	-	Removed a clear-host and pause command from the function to Unlock Site collections
	-	Other minor fixes to output formatting to clean up readability

	Known Issues
		FIXED - Logging - is not working correctly. Disabled for now

V 1.0:
	- 	First Official version. Has functions that are to be used primarily in a SharePoint environment that
		do not allow SharePoint to work as intended when using SP Managed Accounts to manage service account password changes.
	
	-	To do: 
		-	Move editable variables / values to the top of the script
		DONE -	Add checks for locked out accounts to AD password changes 
		DONE -	Add checks for locked out accounts to SP Managed Account Password changes
		DONE -	Other things I haven't thought of yet.	
	
	-	Some features include:
		-	Fully menu driven. Just run the script as an administrator
		- 	Check against list of accounts to confirm if the AD accounts are locked and will attempt to unlock them for you
		- 	(SharePoint) Lock and Unlock Site collections (Must be configured to match your environment. Sorry about it not being easier)
		-	(SharePoint) Start and Stop all SharePoint Timer Services on each SharePoint server
		-	Check against list of credentials to determine if App Pools using those credentials are running and will try to start them.
		-	Check against list of credentials to determine if Windows Services using those credentials are running and will try to start them
		-	Will change passwords in Active Directory if required csv file is provided (See Parameters)
		-	Will change passwords for App Pools and Windows Services on each server using required csv file (See Parameters)
		-	(SharePoint) Will display list of SharePoint farm servers and their roles (may need to be configured depending on environment)
		
.REQUIREMENTS
		-	Powershell 3.0 or higher
		-	WinRM must be enabled and remote Powershell must also be enabled
			- Check if WinRM is running by using this PowerShell command as admin: get-service winrm
				- If not running, run the following PowerShell command as admin: Enable-PSRemoting –force
			- Check firewall and make sure the following firewall rules are open on the server using the 'Windows Firewall with Advanced Security'
				* Windows Remote Management - Compatibility Mode (HttP-IncludePortInSPN)
				* Window Remote Management (HTPP-In)
		- The following commands may need to be run on all of the servers running IIS if using 2008 R2 server
				* Import-Module ServerManager
				* Add-WindowsFeature Web-Scripting-Tools
		- 	Run this PowerShell one-time only on the server running this script: Add-WindowsFeature RSAT-AD-PowerShell
		-	Service Principle Names (SPNs) may be required for your systems depending on the environment
			-	Special SPNs were required for the Powershell port (5985 and 5986 (SSL))
				Example: 	setspn -s HTTP/Server-Short-Name-001:5985 Server-Account-Name-01
							setspn -s HTTP/Server-Long-Name-001-Is-Very-Long-:5985 Server-Account-Name-01
							setspn -s HTTPS/Server-Short-Name-001:5986 Server-Account-Name-01
							setspn -s HTTPS/Server-Long-Name-001-Is-Very-Long-:5986 Server-Account-Name-01	
#>


### Parameters that should only be changed if absolutely necessary ###
# Needs to be cleaned up. Not needed as Parameters.
[cmdletbinding()]
param(
[string] $Global:InputFile = "c:\Allowed\Scripts\accounts.csv",
[switch] $newPasswords = $false)

## Set the TimeOut limit in seconds for the background jobs. 60-120 seconds does not seem to be long enough in some environments
$JobTimeout = '300'

#get the date and time for log file creation
$logtime = get-date -format yyyy-MM-dd_HH-mm-ss
#Set the Log file location. 
$Global:Logfile = "c:\Allowed\Scripts\SharePointTaskLog_$logtime.log"

################################################## 
# Check for Admin Privileges
##################################################
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!`n(Right-Click Powershell Icon, Click 'Run as Administrator')"
    Break
} ###############################################




### Add Snappin
Add-PSSnapin Microsoft.Sharepoint.Powershell

####################################
# Logging and Output Function
####################################
<#
Requirements: Log file path set for variable $logfile
Usage:  Generates output for both the console and for a log file
Example: LoggerLee -Text "error message or $ErrorMsg" -Logtype "error"
Author(s): Lee Dickey & Jason Radcliff

#>
function LoggerLee() {
    [CmdletBinding()]
    param 	(
        [parameter(Mandatory=$True)]  [String]$text,
        [ValidateSet("low","info","warning","error","success")][string]$logType = "info",
        [ValidateSet("newline","nonewline")][string]$linebreak = "newline"         
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

LoggerLee -text "Logfile Created $logtime`n" -LogType Info -linebreak newline
Cipher /E $logfile | out-null


##################################################################
# Getting the SharePoint servers the SharePoint way!
##################################################################
# NOTE:  This is for EPM2016 environment. 
# Other SharePoint farms may have other server roles!
##################################################################
function GetSharePointServers
{
# Get Search Servers
$Global:SearchServers = (Get-SPServer | Where-Object {($_.Role -eq "Search")} | Select-Object @{Name = "ServerName"; Expression = {$_.Address}} | ConvertTo-CSV -NoTypeInformation | Select-Object -skip 1 | % {$_ -replace '"',''}) | Out-String

# Get SSRS Server
$Global:SSRSservers = (Get-SPServer | Where-Object {($_.Role -eq "custom")} | Select-Object @{Name = "ServerName"; Expression = {$_.Address}} | ConvertTo-CSV -NoTypeInformation | Select-Object -skip 1 | % {$_ -replace '"',''}) | Out-String

# Get Application servers
$Global:APPServers = (Get-SPServer | Where-Object {($_.Role -eq "Application")} | Select-Object @{Name = "ServerName"; Expression = {$_.Address}} | ConvertTo-CSV -NoTypeInformation | Select-Object -skip 1 | % {$_ -replace '"',''}) | Out-String

# Get Cache servers
$Global:CacheServers = (Get-SPServer | Where-Object {($_.Role -eq "DistributedCache")} | Select-Object @{Name = "ServerName"; Expression = {$_.Address}} | ConvertTo-CSV -NoTypeInformation | Select-Object -skip 1 | % {$_ -replace '"',''}) | Out-String

# Get Web Servers
$Global:WebServers = (Get-SPServer | Where-Object {($_.Role -eq "WebFrontEnd")} | Select-Object @{Name = "ServerName"; Expression = {$_.Address}} | ConvertTo-CSV -NoTypeInformation | Select-Object -skip 1 | % {$_ -replace '"',''}) | Out-String

# Get Database Server
$db = (Get-SPDatabase)[0]
$Global:DBServers = $db.Server.Address

# Full list of SharePoint Servers in the farm (except DB)
$Global:Servers = Get-SPServer | Where-Object {$_.Role -ne "Invalid"} | select DisplayName
$Global:SPServers = $Servers.DisplayName
}
GetSharePointServers



######################################################
### Acquires required accounts for SharePoint farm ###
######################################################
function Get-Accounts
	{
		LoggerLee "`n`nBuilding list of AD accounts...`n`n" info
		if($Global:accounts)
			{$Global:accounts = $null}
		
		Start-Sleep 5
		
		$Global:accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	
	}


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


######################################################################
# Check to verify that remote access is possible via Invoke-Command
######################################################################
function WinRMVerify
{
remove-job *
LoggerLee "`n`nVerifying the script can access each of the servers to perform remote actions....`n`n" info

###*****************************************************************************************###
### Checks all of the servers to ensure the invoke-command will work. Most everything else 
### will not work if this check fails.
###*****************************************************************************************###
foreach ($system in $SPServers) 
{
	$SessionOption = New-PSSessionOption -IncludePortInSPN

	Try 
		{
		    Invoke-Command -ComputerName $system -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock  {
               
               $result = [PSCustomObject]@{
               Success = $false
               Message = $null
               Completed = $false
               Serv = $using:system
               }  
                  
            Try
                    {
			            $result.message = "Remote Access successful on $Using:system`n"
                        Write-Output $result.message -ErrorAction stop
                        $result.success = $true
                    }

            Catch
                    {
                        $result.message = $_.Exception.Message;
                        $result.success = $false
                    }

$result
} -AsJob | Out-Null
}
Catch { 
        LoggerLee "Could not invoke a remote connection to $server`n" warning; 
        LoggerLee "$_.Exception.Message" error;
		exit	
      }
} 
	#Start of Jobs retrieval
	        $jobs = get-job # | wait-job -timeout 120
            foreach ($job in $jobs){
		    WaitForJob $job.name "Completed"
            $jobresult = $job | receive-job

            if ($jobresult.success -eq $true) 
				{
					LoggerLee -text "$($jobresult.message)" success
				}

            else 
				{
					LoggerLee "This was a failure on $($jobresult.serv)" warning;
					LoggerLee "$($jobresult.message)`n`n" error  
				} }					
				
# Clears or resets variables
$accounts = $null 
remove-job *
}

#########################################################
# (SharePoint) Locking the Site Collections 
#########################################################
function LockSPSites
{
# Collects list of Site Collections that are primarily used while avoiding mysites and other junk
# Will need to be modified to match different SharePoint environments

$SiteCollection = Get-SPSite | Where-Object {($_.Url -match "epm16") -or ($_.Url -match "epm16-my") -and ($_.Url -notmatch "personal") } | select Url
$SiteCollections = $SiteCollection.Url
LoggerLee -Text "`n`nLocking the site collections...." Warning
Start-Sleep -s 5
foreach ($sc in $SiteCollections)
    { 
		#Locks the site collections to prevent corruption to the database
		#if someone tries to make changes while everything is going on
        Try
            {
                Set-SPSite -Identity $sc -LockState "ReadOnly" -ErrorAction Stop; 
                LoggerLee -Text "Locked the site collection: $sc" -LogType Success 
            }

        Catch
            { 
              LoggerLee -Text "Cannot lock site collection: $sc" Error;
			  LoggerLee -Text "Please check the logs for details." Error;
			  LoggerLee $_.Exception.Message Error 
            }			  
    }
		#Pause
}

###########################################################
# (SharePoint) Unlocking the site Collections
###########################################################
function UnlockSPSites
{

#Collects list of Site Collections that are primarily used while avoiding mysites and other junk
$SiteCollection = Get-SPSite | Where-Object {($_.Url -match "epm16") -or ($_.Url -match "epm16-my") -and ($_.Url -notmatch "personal") } | select Url
$SiteCollections = $SiteCollection.Url

LoggerLee "`n`nUnlocking Site Collections....`n" Warning 
foreach ($sc in $SiteCollections)
    { 
		 # Unlocks the site collections that are typically used for typical use
        Try
            {
                Set-SPSite -Identity $sc -LockState "Unlock" -ErrorAction Stop;
                LoggerLee "Unlocked the site collection: $sc" Success 
            }

        Catch
			{ 	LoggerLee "Cannot Unlock site collection: $sc" Error;
				LoggerLee "Please check the logs for details" Error;
				LoggerLee $_.Exception.Message Error
			}
    }
LoggerLee "`nTask Completed.`n`n" Info
#Pause
#cls
}


###########################################################
# Restart all of the servers (not DB)
###########################################################
function RestartFarm
{
#Start-Transcript -Path $Logfile -IncludeInvocationHeader -Append -Force
LoggerLee "`n`n`nSharePoint Servers (Not SQL) to be restarted!" Info
LoggerLee "Type 'Yes' and press enter to restart all SharePoint servers (not DB server)!" Warning
$RestartSPServers = Read-Host 'Yes or No (Default Yes)  >>'  

if (($RestartSPServers -eq 'Yes') -or ($RestartSPServers -eq "y"))
{
# Rebuilds the server list excluding the current logged in system to avoid rebooting the system you are currently using
$SPServers = $SPServers | Where-Object {$_ -ne $env:computername}
foreach ($server in $SPServers) {
Try 	
        {
			LoggerLee "Restarting $server..." Info;
            restart-computer -computername $server -ErrorAction stop ;
            LoggerLee "$server successfully restarted" success
			Start-Sleep -s 2
		}
Catch 	
        {
			LoggerLee "Unable to restart $server. Investigate and restart manually asap!" Error;
            $restarterror1 = "$_.Exception.Message";
			LoggerLee -text $restarterror1 -LogType Error;
			Pause
		}
} 
    LoggerLee "`n`nAll other servers have been restarted. This server (you are on) must now be restarted." Warning;
    LoggerLee "`nSave all work and press ENTER to reboot this system." Info;
    pause;
    LoggerLee "`nAfter this system reboots, give all processes and services 5 to 10 minutes to start up before you continue." warning;
    Start-Sleep -s 30;

Try
	{
        LoggerLee "`nRestarting system $env:computername...`n" Info
		restart-computer -computername "$env:computername" -ErrorAction Stop;
        LoggerLee "$env:computername successfully restarted`n" Success       
	}
	
Catch
	{	
		LoggerLee "Unable to reboot this server $server. Manually restart when ready" error;
		$restarterror2 = "$_.Exception.Message";
        LoggerLee $restarterror2 error
	}
		
Finally 
	{
		LoggerLee "Please manually restart any servers that did not restart then continue!" info;
		Pause	
	}
}

else 
	{LoggerLee "`n`nExited without restarting the SharePoint App and Web servers. This may be required at a later time." warning}
#Stop-Transcript
}


#####################################
# Prompt to restart SQL Server
#####################################
function RestartSQL
{
cls
LoggerLee "Type Yes to restart the database server $DBServers" warning
LoggerLee "`nType 'Yes' or press enter in order to restart the server" info
$RestartDB = Read-Host ' Restart SQL Servers? Yes or No. (Default No) '  
if (($RestartDB -eq 'Yes') -or ($RestartDB -eq 'y'))
	{		
		Try {				
                LoggerLee "`n`nRestarting the database server $DBServers....`n"  info
				Restart-Computer -ComputerName $DBServers -Force -ErrorAction Stop;
				#While (Test-Connection -Quiet -Delay 1 $DBServers) {Write-Host "Waiting for $DBServers to restart and go offline..."}
				Start-Sleep 120
				#While (!(Test-Connection -Quiet -Delay 7 $DBServers)) {Write-Host "Waiting for $DBServers to come back online"}
				LoggerLee "$DBServers back online!" success;
				LoggerLee "`nSQL Server restart completed.`n" success;
				Pause;
			}

		Catch 
			
            {	
				LoggerLee "Failed to restart SQL Server." error;
				LoggerLee "Please manually restart the server and then Press Any Key to continue `n `n `n" warning;
				$restarterror3 = "$_.Exception.Message";
                LoggerLee "$restarterror3`n" error
				Pause;
			}		
	}
	
else {LoggerLee "`n`nCancelling SQL Server restart on $DBServers.`n`n" info} 
} 


########################################
# AppPool password changes
########################################
function UpdateAppPools
{
remove-job *	
#LoggerLee "Updating Passwords for the App Pools....`n`n" Warning

### Grabs the accounts to be changed in the global variable of $accounts
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$newpwd1 = $_.NewPassword
$username = $_.Username
#$newpassword = ConvertTo-SecureString -String $newpwd1 -AsPlainText -Force
LoggerLee -text "`n`nUpdating App Pool Passwords for the account: " info -linebreak nonewline
LoggerLee -text " $username...`n" info
Foreach ($server in $SPServers)
{
Try {

$SessionOption = New-PSSessionOption -IncludePortInSPN #Forces the port specified in the SPN
Invoke-Command -ComputerName $server -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock { #Uses the session created above using the port in the SPN
			
			$result = [PSCustomObject]@{
            Success = $false
            Message = $null
            Completed = $false
            Serv = $using:server
               }  
			   
Import-Module WebAdministration 

  $applicationPools = Get-ChildItem IIS:\AppPools | where { $_.processModel.userName -eq "$Using:username" }
  $Pools = $applicationPools.name
	if($applicationPools) 
        {
            $result.message += "`nAppPools using the $Using:username account are being updated on $Using:server...`n"      
        		 
			foreach($pool in $applicationPools)
			   {
			    #Using Unencrypted credentals due to errors with using the encrypted password
                $un = $Using:username
                $pw = $Using:newpwd1				
					Try 
						 {
							$pool.processModel.userName = "$un";
							$pool.processModel.password = "$pw";
							$pool.processModel.identityType = 3;
							$result.message += "`nChanging password for '$($pool.name)' to $pw... `n" ;
							$pool | Set-Item -ErrorAction Stop; 							
                            $result.message += "Password changed successfully!`n`n";
							$result.success = $true
                         }

					 Catch
						  {
							$result.message += "Failure on the password Change for $($pool.name) `n";
                            write-output $_.Exception.message;
							$result.message += $_.Exception.Message;
							$result.success = $false 
						  }						  
				}
		}
	else {
            $result.success = $true;
            $result.message = "No App Pool password to update on $using:server with account $using:username...`n"
         }	
	 $result		
	#Exit-PSSession	
	}  -AsJob | out-null #-JobName UpdateAppPoolz | Out-Null  		
}	

Catch 
    { 
        LoggerLee "Could not invoke a remote connection to $server!`n" warning; 
        LoggerLee "$($_.Exception.Message)" error;
    } 
}
        $jobs = get-job # | wait-job -timeout 120
        foreach ($job in $jobs){
		WaitForJob $job.name "Completed"
        $jobresult = $job | receive-job

            if ($jobresult.success -eq $true) 
				{
					#LoggerLee -text "Success on $($jobresult.serv)" warning;
					LoggerLee -text "$($jobresult.message)" success
				}

            else 
				{
					LoggerLee "This was a failure on $($jobresult.serv)" warning;
					LoggerLee "$($jobresult.message)`n`n" error  
				} 							
					#write-host $jobresult.success				
}
remove-job *
}
}# End of App Pools Password changes


########################################
# Start any stopped App Pools
########################################
function Start-AppPools
{
#This may need to be modified to match whichever configuration is being used. This should be assigned as a paramater above
$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

LoggerLee "`n`n`nChecking for any App Pools that are enabled and not running....`n`n`n" info

$accounts = ConvertFrom-Csv $accounts 
$accounts | foreach {
$username = $_.Username #Pulled from the Username column

#Pulled from a global variable-function that programatically pulls the SharePoint servers. Can be done via array
Foreach ($server in $SPServers) 
{
	#Write-Host "`n`n`n`nConnecting to $server to check for stopped App Pools using $username...`n" -ForegroundColor DarkGreen -BackgroundColor Cyan
Try {
$SessionOption = New-PSSessionOption -IncludePortInSPN #Forces the port specified in the SPN

Invoke-Command -ComputerName $server -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock { #Uses the session created above using the port in the SPN
			$result = [PSCustomObject]@{
            Success = $false
            Message = $null
            Completed = $false
            Serv = $using:server
               } 

Import-Module WebAdministration
 
	# Pulls the app pool list based on the credentials and whether it is stopped. 
	$applicationPools = Get-ChildItem IIS:\AppPools | where { ($_.processModel.userName -eq "$Using:username") -and ($_.state -eq "Stopped") }

		  $Pools = $applicationPools.name # Not sure why this is here to be honest. Not used anywhere but left in case it's ever needed
		  
			if($applicationPools) # Only runs the below process if there are any app pools to run against (if not null)
				{ 				 
					foreach($pool in $applicationPools)
					   {
							# Many powershell Commandlets and commands do not like variables pulled directly from outside of the invokation
							$AppPool = $pool.name 
							#Write-Host "`nChecking to see if $AppPool pool is running on"$Using:server"" -BackGroundColor White -ForeGroundColor Blue						

								Try 
									 {
                                        $result.message += "Attempting start of '$AppPool'...`n";    
										(Start-WebAppPool -ErrorAction Stop -Name "$AppPool");
										$result.message += "Completed successfully!`n`n";
							            $result.success = $true 								
									  }

								 Catch
									  {
							            $result.message += "*******Action Failed*********** `n";
							            $result.message += $_.Exception.Message;
							            $result.success = $false 
									  }
						}
				}

			Else {
                    $result.success = $true;
                    $result.message += "No Action to take on $using:server `n`n`n"
                  }

$result
} -AsJob | Out-Null
}
Catch { 
        LoggerLee "Could not invoke a remote connection to $server`n" warning; 
        LoggerLee "$_.Exception.Message" error        
      }
} 

	#Start of Jobs retrieval
	        $jobs = get-job # | wait-job -timeout 120
            foreach ($job in $jobs){
		    WaitForJob $job.name "Completed"
            $jobresult = $job | receive-job

            if ($jobresult.success -eq $true) 
				{
					#LoggerLee -text "Success on $($jobresult.serv)" warning;
					LoggerLee -text "$($jobresult.message)" success
				}

            else 
				{
					LoggerLee "This was a failure on $($jobresult.serv)" warning;
					LoggerLee "$($jobresult.message)`n`n" error  
				} }	
				
				
# Clears or resets variables
$accounts = $null 
remove-job *
}}




########################################
# Windows Services password changes
########################################
function Set-WindowsServicesCreds
{
LoggerLee "Changing Passwords for any Windows services that are using the service accounts...`n" Warning
Get-Accounts

### Grabs the accounts to be changed in the global variable of $accounts
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$newpwd1 = $_.NewPassword
$username = $_.Username
$newpassword = ConvertTo-SecureString -String $newpwd1 -AsPlainText -Force

Foreach ($server in $SPServers)
{
Try {
$SessionOption = New-PSSessionOption -IncludePortInSPN
Invoke-Command -ComputerName "$server" -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock {

			$result = [PSCustomObject]@{
            Success = $false
            Message = $null
            Completed = $false
            Serv = $using:server
               } 

$result.message += "Checking for services that use the account: $Using:username on $Using:server... `n"

$WinServices = Get-CimInstance win32_service | Where {$_.StartName -eq "$Using:username"}

if($WinServices)
{
	foreach ($s in $WinServices)    
		{     
			if($s) 
				{
				
					$serv = $s.Name # Must use short name and cannot use the '$Using:' method in CIM commands
					$pass = $Using:newpwd1 # Cannot use '$Using:' and Encrypted password for CIM methods **CONFIRMED**
						
					Try
						{   
							$result.message += "Changing password for '$($s.Name)' to $Using:newpwd1 on $Using:server...`n";
							Invoke-CimMethod -ErrorAction stop -Name Change -Arguments @{StartPassword="$pass"} -Query "Select * from Win32_service where Name='$serv'" | out-file "c:\allowed\scripts\CIMresults.txt" ; #Verify a '0' status code in this file if necessary (0 means successful)	
							$result.message += "Completed Successfully!  `n`n";	
							$result.success = $true 	
						}
						
					 Catch
					 {
					        $result.message += "*******Action Failed*********** `n";
							$result.message += $_.Exception.Message;
							$result.success = $false 
					 }	
				}
		} 
}  

Else {
         $result.success = $true;
         $result.message += "No Action to take on $using:server `n`n"
     }

$result

} -AsJob | Out-Null
}
Catch { 
        LoggerLee "Could not invoke a remote connection to $server`n" warning; 
        LoggerLee "$_.Exception.Message" error        
      }
} 

	#Start of Jobs retrieval
	        $jobs = get-job # | wait-job -timeout 120
            foreach ($job in $jobs){
		    WaitForJob $job.name "Completed"
            $jobresult = $job | receive-job

            if ($jobresult.success -eq $true) 
				{
					LoggerLee -text "$($jobresult.message)" success
				}

            else 
				{
					LoggerLee "This was a failure on $($jobresult.serv)" warning;
					LoggerLee "$($jobresult.message)`n`n" error  
				} }					
				
# Clears or resets variables
$accounts = $null 
remove-job *
}}



###########################################################################
# (SharePoint) Restart Windows Services
###########################################################################
function Restart-WindowsServices
{

#Get List of accounts
$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

LoggerLee "`n`n`nRestarting Windows services....`n`n" warning

#Loops a list of user accounts to check on each server 
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$username = $_.Username

foreach ($srv in $SPServers)
    {   
    
    Try {     
        #Write-Host "`n`n`n`nConnecting to $srv to check for stopped services using $username...`n" -ForegroundColor DarkGreen -BackgroundColor Cyan
        $SessionOption = New-PSSessionOption -IncludePortInSPN
        Invoke-Command -ComputerName $srv -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock {

        	$result = [PSCustomObject]@{
            Success = $false
            Message = $null
            Completed = $false
            Serv = $using:srv
               } 
       
        $WinServices = Get-CimInstance win32_service | Where {(($_.StartName -eq "$Using:username") -and ($_.State -eq "Running") -and ($_.StartMode -ne "Disabled") )}
         
        if($WinServices)
                {   
					foreach ($srvc in $WinServices)	
						{
							$service = $srvc.DisplayName
							$svc = $srvc.Name                          
					  
							Try 
									{
        								Restart-Service -DisplayName $service -ErrorAction Stop; 
										$result.message += "`nSuccessfully Restarted '$service' on $Using:srv `n`n" ;
                                        $result.success = $true 	
									}

							Catch 
									{
										$result.message += "`n`nService could not be restarted on $using:srv" 
							            $result.message += $_.Exception.Message;
							            $result.success = $false 			
									}                       
						}			
                }	
				
Else {
         $result.success = $true;
         $result.message += "No Action to take on $using:srv `n`n"
     }

$result

} -AsJob | Out-Null
}
Catch { 
        LoggerLee "Could not invoke a remote connection to $srv " warning; 
        LoggerLee "$_.Exception.Message" error        
      }
} 

	#Start of Jobs retrieval
	        $jobs = get-job # | wait-job -timeout 120
            foreach ($job in $jobs){
		    WaitForJob $job.name "Completed"
            $jobresult = $job | receive-job

            if ($jobresult.success -eq $true) 
				{
					LoggerLee -text "$($jobresult.message)" success
				}

            else 
				{
					LoggerLee "This was a failure on $($jobresult.serv)" warning;
					LoggerLee "$($jobresult.message)`n`n" error  
				} }					
				
# Clears or resets variables
$accounts = $null 
remove-job *
}}



########################################
# Recycle SharePoint specific AppPools
########################################
function Recycle-AppPools
{
remove-job *
#This may need to be modified to match whichever configuration is being used. This should be assigned as a paramater above
$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

LoggerLee "`nRecycling / Restarting any SharePoint AppPools....`n`n" 

$accounts = ConvertFrom-Csv $accounts 
$accounts | foreach {
$username = $_.Username #Pulled from the Username column

#Pulled from a global variable-function that programatically pulls the SharePoint servers. Can be done via array
Foreach ($server in $SPServers) 
{	
Try {
        $SessionOption = New-PSSessionOption -IncludePortInSPN #Forces the port specified in the SPN
        Invoke-Command -ComputerName $server -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock { #Uses the session created above using the port in the SPN

        	$result = [PSCustomObject]@{
            Success = $false
            Message = $null
            Completed = $false
            Serv = $using:server
               } 

        Import-Module WebAdministration
 
	        # Pulls the app pool list based on the credentials and whether it is stopped. 
	        $applicationPools = Get-ChildItem IIS:\AppPools | where { ($_.processModel.userName -eq "$Using:username") -and ($_.state -eq "Started") }

		          $Pools = $applicationPools.name # Not sure why this is here to be honest. Not used anywhere but left in case it's ever needed
		  
			        if($applicationPools) # Only runs the below process if there are any app pools to run against 
				        { 				 
					        foreach($pool in $applicationPools)
					           {
                                    # Many powershell Commandlets and commands do not like variables pulled directly from outside of the invokation
							        $AppPool = $pool.name 
							        #Write-Host "`nChecking to see if $AppPool pool is running on"$Using:server"" -BackGroundColor White -ForeGroundColor Blue						

								        Try 
									         {
										            (Restart-WebAppPool -ErrorAction Stop -Name "$AppPool");
                                                    $result.message += "`nRecycled $AppPool on $Using:server`n" ;    	
							                        $result.success = $true 										        							
									          }
								        Catch
					                         {
					                              $result.message += "`n*******Action Failed*********** `n";
							                      $result.message += $_.Exception.Message;
							                      $result.success = $false 
					                         }	
						        }
				        }
                        Else 
							{
                                 $result.success = $true;
                                 $result.message += "No Action to take on $using:server `n`n`n"
                             }
$result
} -AsJob | Out-Null
}
Catch { 
        LoggerLee "Could not invoke a remote connection to $server`n" warning; 
        LoggerLee "$_.Exception.Message" error        
      }
} 
	#Start of Jobs retrieval
	        $jobs = get-job # | wait-job -timeout 120
            foreach ($job in $jobs){
		    WaitForJob $job.name "Completed"
            $jobresult = $job | receive-job

            if ($jobresult.success -eq $true) 
				{
					LoggerLee -text "$($jobresult.message)" success
				}

            else 
				{
					LoggerLee "This was a failure on $($jobresult.serv)" warning;
					LoggerLee "$($jobresult.message)`n`n" error  
				} }									
# Clears or resets variables
$accounts = $null 
remove-job *
}}


###########################################################################
# (SharePoint) Updates Passwords SharePoint Managed Accounts
###########################################################################
function UpdateSPManagedAccounts
{
LoggerLee "`n`n Starting process to change passwords in the SharePoint Farm itself...`n`n" warning

	if ($FunctionCheck -eq "yes") {
# Grabs the accounts to be changed in the tempcsv and changes the passwords 
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$newpwd1 = $_.NewPassword
$username = $_.Username
$newpassword =  ConvertTo-SecureString -String $newpwd1 -AsPlainText -Force

if ($newpassword)
{
Try		{
			# This assumes that the passwords are already changed in AD. 
			LoggerLee -text “`n`n`nChanging SharePoint passwords for $username to $newpwd1...” -logType info -linebreak newline
			Set-SPManagedAccount -Identity $username -ExistingPassword $newpassword -Confirm:$false -UseExistingPassword:$true -ErrorAction Stop 
			LoggerLee "Password Changed Successfully.`n" success
		}

Catch 	{
			LoggerLee "Error received updating the service account via Managed Accounts! Please review the logs and try again`n" warning;
			LoggerLee "$_.Exception.Message" error
			#exit
		}
} # End If
}
LoggerLee "`n`nPausing for 1-minute to give the Timer Services time to process the changes across the farm..." info
Start-Sleep 60
}
else 
	{
		LoggerLee "`nThis function must be launched from another function. Cancelling Action!" error;
		Exit
	} 
}## End of UpdateSPManagedAccounts function


###########################################################
# Checking if Accounts locked out in AD
###########################################################
function Check-LockedOut
{
$ADaccounts = (Import-Csv $InputFile | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	
$users = ConvertFrom-Csv $ADaccounts 

LoggerLee "`n`nChecking Account lockout status...`n" Warning
	
# Removes the domain and back-slash	from the username
Foreach ($user in $users)
		{
            $un = $user.username.split('\')[-1]
            $pw = $user.newpassword

                $locked = (Get-Aduser $un -Properties LockedOut).LockedOut
				
					if($locked) 
						{
							LoggerLee "`n$un is Locked out!`n" Warning
							LoggerLee "Attempting to unlock the account..." info
								Try 
										{
											Unlock-ADAccount -Identity $un -ErrorAction Stop;
											LoggerLee "`nAccount $un is now unlocked!`n`n" success						
										}
								Catch
										{
											LoggerLee "`nCould not unlock the account. Verify and manually update the password!`n`n" warning
										}	LoggerLee "$_.Error.Message" error			
						}
					
					else {LoggerLee "`n$un is not locked out!" info}
		}
}


###########################################################
# Updates Passwords in AD based on the $accounts variable
###########################################################
function UpdateAD
{

# Imports AD functionality
Import-Module ActiveDirectory
LoggerLee "`nAD module imported...`n" low

# Required because pulling directly from using the 'Global' method fails every time
if($Global:accounts) {$accounts = $Global:accounts}

# Pulls in the specific accounts from the temp csv file to be changed
$users = ConvertFrom-Csv $accounts 

LoggerLee "Starting AD password changes...`n`n" info
	
# Changes the AD passwords after removing the domain and back-slash	
Foreach ($user in $users)
		{
            $un = $user.username.split('\')[-1]
            $pw = $user.newpassword

					Try {
							$dn = Get-aduser $un | select -ExpandProperty DistinguishedName 
							LoggerLee "Changing passwords in AD for $un to $pw...`n" info
							Set-ADAccountPassword $dn -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $pw -Force) -ErrorAction Stop 
							LoggerLee "Password change successful`n" success
						}
			
		        Catch 	{
					        LoggerLee "`n`nError changing passwords in AD. Manually change the passwords in ADUC and then continue with the process once completed.`n" error
							LoggerLee "$_.Exception.Message" error		
							
				        }		
		}
		
	LoggerLee "`nWaiting for AD changes to Synchronize`n`n" warning;
	Start-Sleep 30;
	LoggerLee "Sync Complted`n" info
	#Pause
	#cls
}
	 
 
 ########################################
 # (SharePoint) Stop Timer Service ######
 ########################################
 function StopTimerServices
 {
	LoggerLee "`n`nStopping and disabling the SharePoint Timer service!`n" warning
		  foreach ($server in $SPServers) 
			{
				Try 
						{
							Set-Service -Name "SPTimerV4" -Status Stopped -StartupType Disabled -PassThru -ComputerName $server | Out-Null -ErrorAction Stop;
							LoggerLee "Timer Service Stopped and Disabled on $server" success
						}

				Catch 
						{
							LoggerLee "`nCould not stop the Timer service on $server. Manually disable and stop it!`n" warning;
							LoggerLee "$_.Exception.Message" error
						}
			} 
} 
 
 
 
########################################
# (SharePoint) Start Timer Service #####
########################################
function StartTimerServices
{
LoggerLee "`n`nRESTARTING TIMER SERVICE ON ALL OF THE SERVERS!" info

foreach ($server in $SPServers) 
	{
		Try 
				{
					Set-Service -Name "SPTimerV4" -StartupType Automatic -Status Running -PassThru -ComputerName $server | Out-Null -ErrorAction Stop;
					LoggerLee "Service Enabled and Started on $server`n" success    
				}

		Catch 
				{
					LoggerLee "`n`nService could not be started and enabled on $server" warning;
					LoggerLee "$_.Exception.Message" error
				
				}
	}
} 
 

 
########################################################
#########  Start any Stopped Windows Services ##########
########################################################

function Check-WindowsServices
{

#Get List of accounts to check for stopped services
$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

LoggerLee "`n`nChecking for any Windows Services that are enabled but not running....`n`n" info


#Loops a list of user accounts to check on each server for stopped services
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$username = $_.Username

foreach ($srv in $SPServers)
    {
    Try {
        $SessionOption = New-PSSessionOption -IncludePortInSPN
        Invoke-Command -ComputerName $srv -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock {
            
            $result = [PSCustomObject]@{
            Success = $false
            Message = $null
            Completed = $false
            Serv = $using:srv
               }        
        $WinServices = Get-CimInstance win32_service | Where {(($_.StartName -eq "$Using:username") -and ($_.State -ne "Running") -and ($_.StartMode -ne "Disabled") )}
         
        if($WinServices)
                {   
					foreach ($srvc in $WinServices)	
						{
							$service = $srvc.DisplayName
							$svc = $srvc.Name
					  
							Try 
									{
										Set-Service -Name "$svc" -StartupType Automatic -Status Running -PassThru | Out-Null -ErrorAction Stop;
										$result.message += "`nService $service Enabled and Started on $Using:srv" ;
                                        $result.success = $true 
									}

						     Catch
					                {
					                    $result.message += "`n*******Action Failed*********** `n";
							            $result.message += $_.Exception.Message;
							            $result.success = $false 
					                 }				
							}                        
						}	                			
          Else {
                 $result.success = $true;
                 $result.message += "No Action to take on $using:srv `n`n`n"
               }
		
$result
} -AsJob | Out-Null
} 
Catch { 
        LoggerLee "Could not invoke a remote connection to $srv`n" warning; 
        LoggerLee "$_.Exception.Message" error        
      }
} 
	#Start of Jobs retrieval
	        $jobs = get-job # | wait-job -timeout 120
            foreach ($job in $jobs){
		    WaitForJob $job.name "Completed"
            $jobresult = $job | receive-job

            if ($jobresult.success -eq $true) 
				{
					LoggerLee -text "$($jobresult.message)" success
				}

            else 
				{
					LoggerLee "This was a failure on $($jobresult.serv)" warning;
					LoggerLee "$($jobresult.message)`n`n" error  
				} }					
				
# Clears or resets variables
$accounts = $null 
remove-job *
}}
 
 
############################################################
# Scheduled Tasks Password Change
############################################################ 
function ScheduledTasksChange 
{
Get-Accounts
### Grabs the accounts to be changed in the global variable of $accounts
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$newpwd1 = $_.NewPassword
$username = $_.Username
$newpassword = ConvertTo-SecureString -String $newpwd1 -AsPlainText -Force

Foreach ($server in $SPServers)
{
    Try 
       {
        $SessionOption = New-PSSessionOption -IncludePortInSPN
        Invoke-Command -ComputerName "$server" -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock {

        	    $result = [PSCustomObject]@{
                Success = $false
                Message = $null
                Completed = $false
                Serv = $using:server
                   } 

	    #Gets the tasks using any usernames in the CSV for credentials
	    $ScheduledTasks = Get-ScheduledTask | Where-Object { $_.Principal.UserId -eq $using:username }

	if ($ScheduledTasks)
		{
			foreach ($task in $ScheduledTasks)
				{
		
					Try
							{	# Changes the password for the scheduled task
								Set-ScheduledTask -ErrorAction stop -TaskName "$task" -User $Using:username -Password $using:newpassword 
								$result.message += "`nScheduld Task $task credentials have been updated on $Using:server" 
                                $result.success = $true  
							}
							
					Catch
							{
								$result.message =+ "`nScheduled Task $task could not be updated on $using:server`n" ;
								$result.message += $_.Exception.Message;
							    $result.success = $false 	
							}
				}
		}
		
                   Else 
				        {
                           $result.success = $true;
                           $result.message += "No Action to take on $using:server `n`n`n"
                        }	
		
$result
} -AsJob | Out-Null
}
Catch { 
        LoggerLee "Could not invoke a remote connection to $server`n" warning; 
        LoggerLee "$_.Exception.Message" error        
      }
} 
	#Start of Jobs retrieval
	        $jobs = get-job # | wait-job -timeout 120
            foreach ($job in $jobs){
		    WaitForJob $job.name "Completed"
            $jobresult = $job | receive-job

            if ($jobresult.success -eq $true) 
				{
					LoggerLee -text "$($jobresult.message)" success
				}

            else 
				{
					LoggerLee "This was a failure on $($jobresult.serv)" warning;
					LoggerLee "$($jobresult.message)`n`n" error  
				} }					
				
# Clears or resets variables
$accounts = $null 
remove-job *
}}
 
  
############################################################
# Manually Change passwords on SQL Server 
############################################################
function SQLChanges 
{
LoggerLee "`n`nChanging SQL service account passwords!" Warning
LoggerLee "`nSome of this process is manual so please pay attention...`n`n" info

start-sleep 5

#$ChangePasswords = Read-Host 'Are you sure you want to change the SQL Service Account passwords? Yes or No. (Default no) '  
$SQLaccounts = (Import-Csv $InputFile | Where {(($_ -match "mssql") -or ($_ -match "agent") -or ($_ -match "ssas") -and ($_ -match "Username") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

# Imports AD functionality
Import-Module ActiveDirectory

# Pulls in the specific accounts from the temp csv file to be changed
$users = ConvertFrom-Csv $SQLaccounts

LoggerLee "`n`nStarting AD password changes for SQL related accounts...`n`n`n" Warning
	
# Changes the AD passwords after removing the domain and back-slash	
Foreach ($user in $users)
		{
			
            $un = $user.username.split('\')[-1]
            $pw = $user.newpassword
			
			Try {
					$dn = Get-aduser $un | select -ExpandProperty DistinguishedName 
					LoggerLee "Changing passwords in AD for $un to $pw..." info
					Set-ADAccountPassword $dn -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $pw -Force) -ErrorAction Stop 
                    LoggerLee "Password successfully Changed.`n`n`n" success
                            
				}
			
		    Catch 	
					{
					    LoggerLee "`n`nError changing passwords in AD. Please change the $un password manually in AD and then press Enter to Continue`n" warning; 
                        LoggerLee "$_.Exception.message`n`n" error
					    Pause							
				    }		
		}		
		LoggerLee "`nManually Change the passwords in SQL Server Configuration Manager on the SQL Server..." warning ;
		LoggerLee "Press ENTER to continue after the passwords on the SQL server have been changed!`n`n" info;
		pause
		
		LoggerLee "Task for SQL server password changes end" low
	}




###############################################
# (SharePoint) Get list of SharePoint servers
###############################################
function ListSharePointServers
	{ 
	cls
	if($AppServers)
	{Write-Host "Application Servers:" -BackgroundColor Yellow -ForeGroundColor Blue;
	Write-Host "$APPServers" -ForeGroundColor Green}
	
	if($SSRSservers)
	{Write-Host "SSRS Reporting Servers:" -BackgroundColor Yellow -ForeGroundColor Blue;
	Write-Host "$SSRSservers" -ForeGroundColor Green}
	
	if($SearchServers)
	{Write-Host "Search Service Servers:" -BackgroundColor Yellow -ForeGroundColor Blue;
	Write-Host "$SearchServers" -ForeGroundColor Green}
	
	if($CacheServers)
	{Write-Host "Cache Servers:" -BackgroundColor Yellow -ForeGroundColor Blue;
	Write-Host "$CacheServers" -ForeGroundColor Green}
	
	if($EXCLServers)
	{Write-Host "Excel Reporting Servers:" -BackgroundColor Yellow -ForeGroundColor Blue;
	Write-Host "$EXCLServers" -ForeGroundColor Green}
	
	if($WebServers)
	{Write-Host "Web Servers:" -BackgroundColor Yellow -ForeGroundColor Blue;
	Write-Host "$WebServers" -ForeGroundColor Green}
	
	if($DBServers)
	{Write-Host "SQL Servers:" -BackgroundColor Yellow -ForeGroundColor Blue;
	Write-Host "$DBServers" -ForeGroundColor Green}
	
	Write-Host "`n********************************************************"
	Write-Host "********************************************************`n"
	}
	
	

#########################################
# List Affected Windows Services
#########################################
function ListAffected-WindowsServices
{
cls
#Get List of accounts
$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

LoggerLee "`nAcquiring list of Windows Services that could be affected by other aspects of this script....`n"
LoggerLee "Please be patient....`n" low

#Loops a list of user accounts to check on each server 
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$username = $_.Username

foreach ($srv in $SPServers)
    {        
        #Write-Host "`nChecking for services on $srv`n" -ForegroundColor DarkGreen

Try {
        $SessionOption = New-PSSessionOption -IncludePortInSPN
        Invoke-Command -ComputerName $srv -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock {
                $result = [PSCustomObject]@{
                Success = $false
                Message = $null
                Completed = $false
                Serv = $using:srv
                   } 

        $WinServices = Get-CimInstance win32_service | Where {(($_.StartName -eq "$Using:username") -and ($_.StartMode -ne "Disabled") )}
         
        if($WinServices)
                {  
					$result.message += "`n$Using:srv is using the following: `n"
					foreach ($srvc in $WinServices)	
						{
							$service = $srvc.DisplayName;
							$svc = $srvc.Name;
							$result.message += "`nFound $service using the account $Using:username`n";
                            $result.success = $true     					                   
						}				
			    }	
				
         Else    {$result.success = $null; break  }	

$result
} -AsJob | Out-Null
}
Catch { 
        LoggerLee "Could not invoke a remote connection to $srv`n" warning; 
        LoggerLee "$_.Exception.Message" error        
      }
} 
	#Start of Jobs retrieval
	        $jobs = get-job | wait-job -timeout 120
            foreach ($job in $jobs){
		   # WaitForJob $job.name "Completed"
            $jobresult = $job | receive-job

            if ($jobresult.success -eq $true) 
				{
					LoggerLee -text "$($jobresult.message)" success
				}
            else 
				{
                    if ($jobresult.success -eq $false)
                        {
				        	LoggerLee "This was a failure on $($jobresult.serv)" warning;
				        	LoggerLee "$($jobresult.message)`n`n" error  
                        }
				} }					
				
# Clears or resets variables
$accounts = $null 
remove-job *
}}


########################################
# List Affected AppPools
########################################
function List-AppPools
{
cls
#This may need to be modified to match whichever configuration is being used. This should be assigned as a paramater above
#$accounts = (Import-Csv $InputFile | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

LoggerLee "`nAcquiring list of IIS App Pools that could be affected by other aspects of this script....`n"
LoggerLee "Please be patient....`n" low 

$accounts = ConvertFrom-Csv $accounts 
$accounts | foreach {
$username = $_.Username #Pulled from the 'Username' column

#Only uses the Web Servers
Foreach ($server in $SPServers) #| Where {$_ -match "WB"})
{

Try {
        $SessionOption = New-PSSessionOption -IncludePortInSPN #Forces the port specified in the SPN
        Invoke-Command -ComputerName $server -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock { #Uses the session created above using the port in the SPN

                $result = [PSCustomObject]@{
                Success = $false
                Message = $null
                Completed = $false
                Serv = $using:server
                   } 

        Import-Module WebAdministration
 
		Try 
			{	
	        # Pulls the app pool list based on the credentials and whether it is stopped. 
	        $applicationPools = Get-ChildItem IIS:\AppPools -ErrorAction stop | where { ($_.processModel.userName -eq "$Using:username") }# -and ($_.state -eq "Started") } 
                if ($applicationPools)
                    {
                        $result.message +=  "`n$Using:server is using the following:`n"
                        foreach ($pool in $applicationpools)
                            {
                                $AppPool = $pool.name; 				
								$result.message =  "Found pool '$AppPool' using the account $Using:username on $using:server" ;
                                $result.success = $true   
                            }
                    }

                 Else    {$result.success = $null; break  }	
			}
			
		Catch
			{
				$result.message += "`nCould not retrieve list of App Pools from $using:server`n" ;
				$result.message += "$_.Exception.Message";
			    $result.success = $false 	
		    }			        

$result
} -AsJob | Out-Null
}
Catch { 
        LoggerLee "Could not invoke a remote connection to $srv`n" warning; 
        LoggerLee "$_.Exception.Message" error        
      }
} 
	#Start of Jobs retrieval
	        $jobs = get-job | wait-job -timeout 120
            foreach ($job in $jobs){
		    #WaitForJob $job.name "Completed"
            $jobresult = $job | receive-job

            if ($jobresult.success -eq $true) 
				{
					LoggerLee -text "$($jobresult.message)" success
				}

            else 
				{
                    if ($jobresult.success -eq $false)
                        {
				        	LoggerLee "This was a failure on $($jobresult.serv)" warning;
				        	LoggerLee "$($jobresult.message)`n`n" error  
                        }
				} }					
				
# Clears or resets variables
$accounts = $null 
remove-job *
}}


####################################################
# Main Password Change Function of functions
####################################################
function ChangeSPServiceAccountPasswords #This is the primary function for SharePoint Password changes 
{

### Checks for any running Logging / Transcripts and kills them before starting a new one for this script
#try		{stop-transcript|out-null}
#catch 	[System.InvalidOperationException]{}

#Starts a new log file
#Start-Transcript -Path $Logfile 

# Used for other functions to confirm they are initiated from this primary function
$Global:FunctionCheck = "yes"

Write-Host `n `n `n
Write-Host "This will change the service account passwords." -ForegroundColor Blue -BackGroundColor White
Write-Host "`nDoing this will cause downtime with the SharePoint Farm!" -ForegroundColor Blue -BackGroundColor White
Write-Host "`nAre you sure you want to perform this task??" -ForegroundColor Green
$ChangePasswords = Read-Host ' Start the Service Account password change process? Yes or No. (Default no) '  
if (($ChangePasswords -eq 'yes') -or ($ChangePasswords -eq 'y')) 
	{
	
		#Verifies that all sharepoint servers can be access with 'invoke-command'
		WinRMVerify

		# Creates CSV formated variable to use for determining which accounts get their passwords updated
		# Does not include the SQL and Agent accounts
		Get-Accounts

		# Updates AD
		UpdateAD

		# Updates SharePoint Managed accounts
		UpdateSPManagedAccounts

		# Locks the site collections before changing the passwords in SharePoint
		LockSPSites

		#StopTimerServices
		StopTimerServices

		#Update SQL accounts
		SQLChanges

		#Re-acquire accounts for main system
		#Get-Accounts

		# Update Windows Services
		Set-WindowsServicesCreds
		
		# Update Scheduled TASKS
		#ScheduledTasksChange 

		# Updates the App Pools
		UpdateAppPools

		# Unlocks the site collections before starting the farm
		UnlockSPSites

		# Clears or resets variables
		$accounts = $null
		$FunctionCheck = "no"

		#Start Timer Services
		StartTimerServices

		# Restarts the farm
		RestartFarm
	}

else 
	{
		Write-Host "`n`nPassword change process cancelled!" -ForeGroundColor Red; 
	}
}



	
	
####################################################################
# After Password Change trouble-shooting menu
####################################################################	
 function Post-PasswordChange {
 
 do {
 
 [int]$PTask = 0
 while ($PTask -lt 1 -or $PTask -gt 8)  {
 cls
Write-Host "`n*** THE FOLLOWING TASKS SHOULD ONLY BE PERFORMED AFTER A PASSWORD CHANGE HAS BEEN PERFORMED***`n" -ForeGroundColor Yellow
 
Write-Host  "`n#####  Tasks to manually change passwords in SharePoint farm (accounts.csv must be present)  #####" -ForegroundColor Black -BackgroundColor White
Write-Host  "1.   Change the passwords for the Windows Services"
Write-Host  "2.   Change the passwords for the App Pool Credentials"
Write-Host  "3.   Change SharePoint Managed Accounts passwords"
 
Write-Host  "`n#####  Tasks to check for stopped App Pools and Windows Services and Starts them  #####" -ForegroundColor Black -BackgroundColor White
Write-Host  "4.   Start any SharePoint Application Pools that have stopped" 
Write-Host  "5.   Start any Windows Services that are not running"  

Write-Host  "`n#####  Tasks to restart or recycle currently running Windows Services and App Pools  #####" -ForegroundColor Black -BackgroundColor White
Write-Host  "6.   Restart running Windows Services (SharePoint specific services)" 
Write-Host  "7.   Recycle all SharePoint specific AppPools in IIS" 
 

 Write-Host "`n8.   Exit from this menu" -ForeGroundColor CYAN
 
[int]$PTask = Read-Host "`n`nSelect a task to perform on this farm"

switch($PTask)
		{	
			1	{Set-WindowsServicesCreds; pause}
			2	{Get-Accounts; UpdateAppPools; pause}
			3	{Get-Accounts; UpdateSPManagedAccounts; pause}
			4	{Start-AppPools; pause}
			5	{Check-WindowsServices; pause}
			6	{Restart-WindowsServices; pause}
			7	{Recycle-AppPools; pause}
			8 	{break}
			default	{Write-Host "Nothing Selected"}
			
		}
	}
} While ($PTask -ne 8)	
}	
	
	
	
####################################################################
# Select a desired task to perform on farm
####################################################################

 ## Add new options here and then add them to the $selections line below (leave Exit as last and unnumbered) and add the menu selection at the very bottom
 do {
 
 [int]$Task = 0
 while ($Task -lt 1 -or $Task -gt 18)  {
 cls
 Write-Host  "`n#####  TROUBLE-SHOOTING TASKS  #####" -ForegroundColor Black -BackgroundColor White
 Write-Host  "1.   List SharePoint Servers"
 Write-Host  "2.   Verify Remote Connectivity"
 Write-Host	 "3.   List Windows Services affected by this script"		
 Write-Host	 "4.   List IIS App Pools affected by this script"
 Write-Host  "5.   Check if Accounts Locked"
 Write-Host  "6.   Start any SharePoint Application Pools that have stopped" 
 Write-Host  "7.   Start any Windows Services that have stopped"
  
 Write-Host  "`n#####  PASSWORD CHANGE TASKS  #####" -ForegroundColor Black -BackgroundColor White
 Write-Host  "8.   Change Service Account Passwords (SharePoint)"
 Write-Host  "9.   Encrypt CSV containing passwords"
 Write-Host  "10.  Decrypt CSV and Log file containing passwords"
 Write-Host  "`n     The following task should only be used AFTER option 6 has been completed!" -ForegroundColor Yellow
 Write-Host  "11.  Post Password Change trouble-shooting tasks." 

  
 Write-Host  "`n#####  SYSTEM RESTART OPTIONS  #####" -ForegroundColor Black -BackgroundColor White
 Write-Host  "12.  Restart SharePoint Web and Application Servers"
 Write-Host  "13.  Restart SQL Server(s)"
 
 Write-Host  "`n#####  SHAREPOINT MAINTENANCE TASKS  #####" -ForegroundColor Black -BackgroundColor White
 Write-Host  "14.  Lock SharePoint Site Collections"
 Write-Host  "15.  Unlock SharePoint Site Collections"
 Write-Host  "16.  Stop Timer Services on all SharePoint servers"
 Write-Host  "17.  Start Timer Services on all SharePoint servers"
 
 Write-Host "`n18.  Exit this script" -ForeGroundColor Cyan
 
[int]$Task = Read-Host "`n`nSelect a task to perform"

switch($Task)
		{	
			1	{ListSharePointServers; pause}
			2	{WinRMVerify; pause}
			3	{ListAffected-WindowsServices; pause}
			4	{List-AppPools; pause}
			5	{Check-LockedOut; pause}
			6	{Start-AppPools; pause}
			7	{Check-WindowsServices; pause}
			8	{ChangeSPServiceAccountPasswords; pause}
			9	{Cipher /E $InputFile; pause}
			10	{Cipher /D $InputFile; Cipher /D $Logfile; pause}
			11	{Post-PasswordChange}
			12	{RestartFarm}
			13	{RestartSQL; pause}
			14	{LockSPSites; pause}
			15	{UnlockSPSites; pause}
			16	{StopTimerServices; pause}
			17	{StartTimerServices;pause}
			18 	{exit}
			default	{Write-Host "Nothing Selected"}
			
		}
	}
} While ($Task -ne 18)
