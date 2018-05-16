<#
.SYNOPSIS
Performs multiple tasks for the SharePoint Farm via a menu.
.DESCRIPTION
Changes account passwords using the provided CSV (inputfile), restarts the farm and other tasks.
.EXAMPLE
.\SharePoint2016Tasks.ps1 

.NOTES
Author: Lee Dickey (Lee.A.Dickey@uscg.mil) x2673
Date: 07 May 2018
Version: 3.0

V 3.0 05/07/2018
		- Added commands to encrypt and decrypt the Accounts.csv file.
			* Only the user that encrypted the file can read and decrypt it.
		- Add new commands to list the App Pools and Windows services that will be affected by the scripts other commands
		- Added more details to the .Requirements for firewall permissions, WinRM activation, and PowerShell features
		- Removed outdated and no longer used functions 

V 2.1 06/13/2017:

	- Added new function to restart running Windows Services specific to SharePoint
	- Added new function to recycle AppPools specific to the SharePoint farm
	- Added secondary sub-menu for post-password change troubleshooting tasks (some are dupes)
	- Cleaned up font coloring and text formatting

V 2.0 05/24/2017:
	
	- Enabled parrallel processing of tasks to multiple functions to speed up tasks using PowerShell jobs.
	- Minor text fixes

V 1.2 04/25/2017:

	-	Completely rewrote the menu system which improves functionality in a significant way and shortens the code to 1/3 original length.
	-	Minor text and formatting fixes

V 1.1 04/20/2017: 
	
	-	Corrected output formatting issues with function to start App Pools
	-	Removed a clear-host and pause command from the function to Unlock Site collections
	-	Other minor fixes to output formatting to clean up readability

	Known Issues:
		- Logging - is not working correctly. Disabled for now

V 1.0:

	- 	First Official version. Has functions that are to be used primarily in a SharePoint environment that
		does not allow SharePoint to work as intended when using SP Managed Accounts to manage service account password changes.
	
	-	To do: 
		-	Move editable variables / values to the top of the script
		-	Add checks for locked out accounts to AD password changes
		-	Add checks for locked out accounts to SP Managed Account Password changes
		-	Other things I haven't thought of yet.	
	
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
[switch] $newPasswords = $false,
[string] $Global:Logfile = "c:\Allowed\Scripts\SharePointTaskLog.log")

## Set the TimeOut limit in seconds for the background jobs. 60-120 seconds does not seem to be long enough in some environments
$JobTimeout = '300'


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

######################################################################################################################
##### Function to allow multiple colored text on one line. Makes for nicer feedback ##################################
##### Source: https://stackoverflow.com/questions/2688547/muliple-foreground-colors-in-powershell-in-one-command  ####
######################################################################################################################
function Write-Color([String[]]$Text, [ConsoleColor[]]$Color = "White", [int]$StartTab = 0, [int] $LinesBefore = 0,[int] $LinesAfter = 0) {
$DefaultColor = $Color[0]
if ($LinesBefore -ne 0) {  for ($i = 0; $i -lt $LinesBefore; $i++) { Write-Host "`n" -NoNewline } } # Add empty line before
if ($StartTab -ne 0) {  for ($i = 0; $i -lt $StartTab; $i++) { Write-Host "`t" -NoNewLine } }  # Add TABS before text
if ($Color.Count -ge $Text.Count) {
    for ($i = 0; $i -lt $Text.Length; $i++) { Write-Host $Text[$i] -ForegroundColor $Color[$i] -NoNewLine } 
} else {
    for ($i = 0; $i -lt $Color.Length ; $i++) { Write-Host $Text[$i] -ForegroundColor $Color[$i] -NoNewLine }
    for ($i = $Color.Length; $i -lt $Text.Length; $i++) { Write-Host $Text[$i] -ForegroundColor $DefaultColor -NoNewLine }
}
Write-Host
if ($LinesAfter -ne 0) {  for ($i = 0; $i -lt $LinesAfter; $i++) { Write-Host "`n" } }  # Add empty line after
}


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


######################################################################
# Check to verify that remote acccess is possible via Invoke-Command
######################################################################
function WinRMVerify
{
Write-Host "`n`n`nConfirming that Remote Management is enabled`n" -ForeGroundColor Blue -BackgroundColor White
###*****************************************************************************************###
### Checks all of the servers to ensure the invoke-command will work. Most everything else 
### will not work if this check fails.
###*****************************************************************************************###
foreach ($system in $SPServers) 
{
	$SessionOption = New-PSSessionOption -IncludePortInSPN
	Try # Attemps remote session connection to make sure Remote Management works
		{
			Invoke-Command -ComputerName $system -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock  {
			Write-Host "Remote Access successful on $Using:system" -ForeGroundColor Green;
			Exit-PSSession} -AsJob -JobName RMVerifiez | Out-Null # Executes this script block as a background task
		}

	Catch 
		{
			Write-Host "Unable to remotely connect to $system! with the following error:`n";
			write-Host $_.Exception.Message;
			Exit 
		}
}
# Waits until the backgrounds are completed 
wait-job -Name RMVerifiez -Timeout 60 | Out-Null
# Displays the results of the background tasks once all have been completed
Receive-Job -Name RMVerifiez
# Removes the jobs from memory 
Remove-Job RMVerifiez | Out-Null
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
Write-Host "`n`nLocking the site collections!" -ForegroundColor Blue -BackGroundColor White
Start-Sleep -s 5
foreach ($sc in $SiteCollections)
    { 
		#Locks the site collections to prevent corruption to the database
		#if someone tries to make changes while everything is going on
        Try
            {Set-SPSite -Identity $sc -LockState "ReadOnly" -ErrorAction Continue; 
            Write-Host "Locked the site collection: $sc" -ForeGroundColor Green }

        Catch
            { Write-Host "Cannot lock site collection: $sc" -BackGroundColor Red;
			  Write-Host "Please check the logs for details.";
			  write-Host $_.Exception.Message }
			  
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

Write-Host "`n`nUNLOCKING SITE COLLECTIONS...." -BackGroundColor white -ForegroundColor Blue 
foreach ($sc in $SiteCollections)
    { 
		 # Unlocks the site collections that are typically used for typical use
        Try
            {Set-SPSite -Identity $sc -LockState "Unlock" -ErrorAction Stop;
            Write-Host "Unlocked the site collection: $sc" -ForeGroundColor Green }

        Catch
			{ 	Write-Host "Cannot Unlock site collection: $sc";
				Write-Host "Please check the logs for details";
				write-Host $_.Exception.Message
			}
    }
Write-Host "`nAll site collections have been unlocked.`n`n" -ForegroundColor Green
#Pause
#cls
}



###########################################################
# Restart all of the servers (not DB)
###########################################################
function RestartFarm
{
write-Host "`n`n`nSharePoint Servers (Not SQL) be restarted!" -ForegroundColor Green
Write-Host "Type 'Yes' and press enter to restart all SharePoint servers (not DB server)!" -ForegroundColor DarkYellow
$RestartSPServers = Read-Host 'Yes or No (Default Yes)  >>'  

if (($RestartSPServers -eq 'Yes') -or ($RestartSPServers -eq "y"))
{
# Rebuilds the server list excluding the current logged in system to avoid rebooting the system you are currently using
$SPServers = $SPServers | Where-Object {$_ -ne $env:computername}
foreach ($server in $SPServers) {
Try 	{
			restart-computer -computername $server -Force -ErrorAction Continue;
			write-host "Restarting $server";
			Start-Sleep -s 2;
		}
Catch 	{
			Write-Host "Unable to restart $server. Investigate and restart manually asap!";
			write-Host $_.Exception.Message
			Pause
		}
} 
Write-Host "`n`nAll other servers have been restarted. This server must now be restarted." -ForegroundColor Green;
Write-Host "`nSave all work and press ENTER to reboot this system." -ForegroundColor Green;
pause;
Write-Host "`nAfter this system reboots, give all processes and services 5 to 10 minutes to start up before you continue." -ForegroundColor Blue -BackGroundColor Yellow;
Start-Sleep -s 30;

Try
	{
		restart-computer -computername "$env:computername" -force -ErrorAction Continue;
	}
	
Catch
	{	
		Write-Host "Unable to reboot this server $server. Manually restart when ready";
		write-Host $_.Exception.Message
	}
		
Finally 
	{
		Write-Host "Please manually restart any servers that did not restart then continue!" -ForeGroundColor Red -BackGroundColor Blue;
		Pause	
	}
}

else 
	{
		Write-Host "`n `nExited without restarting the SharePoint App and Web servers. This may be required at a later time." -ForegroundColor Yellow

}
}


#####################################
# Prompt to restart SQL Server
#####################################
function RestartSQL
{
cls
Write-Host "Type Yes to restart the database server $DBServers" -ForegroundColor Blue -BackGroundColor White
Write-Host "`nType 'Yes' or press enter in order to restart the server" -ForegroundColor Green
$RestartDB = Read-Host ' Restart SQL Servers? Yes or No. (Default No) '  
if (($RestartDB -eq 'Yes') -or ($RestartDB -eq 'y'))
	{		
		Try {
				#LockSPSites
				Restart-Computer -ComputerName $DBServers -Force;# -ErrorAction Stop;
				Write-Host "`n`nRestarting the database server $DBServers....`n"  -ForeGroundColor Yellow;
				#While (Test-Connection -Quiet -Delay 1 $DBServers) {Write-Host "Waiting for $DBServers to restart and go offline..."}
				Start-Sleep 120
				#While (!(Test-Connection -Quiet -Delay 7 $DBServers)) {Write-Host "Waiting for $DBServers to come back online"}
				Write-Host "$DBServers back online!" -ForeGroundColor Green;
				Write-Host "`nSQL Server restart completed.`n" -ForeGroundColor Green;
				Pause;
				#UnlockSPSites				
				
			}
		Catch 
			{	
				Write-Host "Failed to restart SQL Server." -ForeGroundColor Red;
				Write-Host "Please manually restart the server and then Press Any Key to continue `n `n `n" -ForeGroundColor Red;
				write-Host $_.Exception.Message;
				Write-Host "`n"
				Pause;
			}
			
		#Finally {UnlockSPSites}
	}
	
else {Write-Host "`n`nCancelling SQL Server restart on $DBServers.`n`n"} 
} 



########################################
# AppPool password changes
########################################
function UpdateAppPools
{	
### Grabs the accounts to be changed in the global variable of $accounts
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$newpwd1 = $_.NewPassword
$username = $_.Username
#$newpassword = ConvertTo-SecureString -String $newpwd1 -AsPlainText -Force

Foreach ($server in $SPServers)
{
Try {
$SessionOption = New-PSSessionOption -IncludePortInSPN #Forces the port specified in the SPN
Invoke-Command -ComputerName $server -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock { #Uses the session created above using the port in the SPN
Import-Module WebAdministration 

  $applicationPools = Get-ChildItem IIS:\AppPools | where { $_.processModel.userName -eq "$Using:username" }
  $Pools = $applicationPools.name
	if($applicationPools) 

		{Write-Host "`n`n"; Write-Host "AppPools using the $Using:username account are being updated on"$Using:server":" -BackGroundColor Yellow -ForegroundColor DarkRed; Write-Host "`n"}
		 
			foreach($pool in $applicationPools)
			   {
			    #Using Unencrypted credentals due to errors with using the encrypted password
                $un = $Using:username
                $pw = $Using:newpwd1
				
					Try 
						 {
							$pool.processModel.userName = "$un"
							$pool.processModel.password = "$pw"
							$pool.processModel.identityType = 3
							Write-Host "Changing password for"$pool.name"to $pw" -BackgroundColor DarkMagenta -ForegroundColor Green
							$pool | Set-Item -ErrorAction Stop 							
						  }

					 Catch
						  {
							Write-Host "No-Go on the password Change";
							write-Host $_.Exception.Message
						  }
				}
	Exit-PSSession	
	} -AsJob -JobName UpdateAppPoolz | Out-Null    

} 
Catch { Write-Host "Could not invoke a remote command to $server!`n" -ForeGroundColor Red; write-Host $_.Exception.Message }    
}
	Wait-Job -Name UpdateAppPoolz -timeout $JobTimeout | out-null
	Receive-Job -Name UpdateAppPoolz
	Remove-Job * | Out-Null 
}
}# End of App Pools Password changes


########################################
# Start any stopped App Pools
########################################
function Start-AppPools
{
#This may need to be modified to match whichever configuration is being used. This should be assigned as a paramater above
$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

Write-Host "`n`n`nChecking for any App Pools that are enabled and not running...." -BackGroundColor White -ForeGroundColor Blue
Write-Host "`nThis may take some time. Please be patient...." -ForeGroundColor Yellow

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
										(Start-WebAppPool -ErrorAction Continue -Name "$AppPool");
										Write-Host "`nStarted AppPool $AppPool on $Using:server" -ForegroundColor White -BackGroundColor Yellow								
									  }

								 Catch
									  {
										Write-Host "`n`nNo-Go on AppPool start for $AppPool on $Using:server with the account $Using:username" -ForegroundColor Red;
										write-Host $_.Exception.Message
									  }
						}
				}
			Else {Write-Host "`nNo App Pools using $Using:username need restarting on $Using:server" -ForeGroundColor Green}
Exit-PSSession
} -AsJob -JobName StartPoolz | Out-Null
}
Catch { Write-Host "Could not invoke a remote command to $server!`n" -ForeGroundColor Red; write-Host $_.Exception.Message }
} 
wait-job -Name StartPoolz -timeout $JobTimeout | Out-Null
Receive-Job -Name StartPoolz
Remove-Job StartPoolz | Out-Null   
}
# Clears or resets variables
$accounts = $null 
}



########################################
# Windows Services password changes
########################################
function Set-WindowsServicesCreds
{

### Grabs the accounts to be changed in the global variable of $accounts
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$newpwd1 = $_.NewPassword
$username = $_.Username
$newpassword = ConvertTo-SecureString -String $newpwd1 -AsPlainText -Force

Foreach ($server in $SPServers)
{
#Write-Host "`n`n`n`nInitiating remote connection to $server...`n" -ForegroundColor DarkGreen -BackgroundColor Cyan
$SessionOption = New-PSSessionOption -IncludePortInSPN
Invoke-Command -ComputerName "$server" -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock {

#Write-Host "`nConnection to $Using:server established!`n" -ForegroundColor Green
Write-Host "`n`nChecking for services that use the account: $Using:username on $Using:server `n" -ForegroundColor Black -BackgroundColor White

$WinServices = Get-CimInstance win32_service | Where {$_.StartName -eq "$Using:username"}

if($WinServices)
{
	foreach ($s in $WinServices)    
		{     
			if($s) 
				{
				
				# The CimMethod is not smart and does not know which property of a value to pull. They must be specified or
				# or the command will fail without notice or feedback. A successful command will generate a '0' status code in the out-file
					$serv = $s.Name # Must use short name and cannot use the '$Using:' method in CIM commands
					$pass = $Using:newpwd1 # Cannot use '$Using:' and Encrypted password for CIM methods **CONFIRMED**
						
					Try
						{   
							Write-Host "Changing password for"$s.Name"to $Using:newpwd1 on $Using:server" -BackgroundColor DarkMagenta -ForegroundColor Green
							Invoke-CimMethod -Name Change -Arguments @{StartPassword="$pass"} -Query "Select * from Win32_service where Name='$serv'" | out-file "c:\allowed\scripts\CIMresults.txt" #Verify a '0' status code in this file if necessary (0 means successful)	
																		
							Write-Host ""
						}
						
					Catch
						{
							Write-Host "No-Go on the password Change";
							write-Host $_.Exception.Message
						}
				} #End of if
	} #End of foreach ($s in $WinServices)   

Exit-PSSession
} # End of If
else {Write-Host "No Windows services to update on $Using:server`n" -ForegroundColor Yellow}
} -AsJob -JobName SetServCredz | Out-Null # End of Invoke / -ScriptBlock
} # End of Foreach ($server in $SPServers)
wait-job -Name SetServCredz -timeout $JobTimeout | Out-Null
Receive-Job -Name SetServCredz
Remove-Job SetServCredz | Out-Null
} # End of $passwords | foreach


} # End of function Set-WindowsServicesCreds





###########################################################################
# (SharePoint) Restart Windows Services
###########################################################################
function Restart-WindowsServices
{

#Get List of accounts
$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

Write-Host "`n`n`nRestarting Windows services...." -BackGroundColor White -ForeGroundColor Blue
Write-Host "`nPlease be patient...." -ForeGroundColor Yellow

#Loops a list of user accounts to check on each server 
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$username = $_.Username

foreach ($srv in $SPServers)
    {        
        #Write-Host "`n`n`n`nConnecting to $srv to check for stopped services using $username...`n" -ForegroundColor DarkGreen -BackgroundColor Cyan
        $SessionOption = New-PSSessionOption -IncludePortInSPN
        Invoke-Command -ComputerName $srv -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock {
       
        $WinServices = Get-CimInstance win32_service | Where {(($_.StartName -eq "$Using:username") -and ($_.State -eq "Running") -and ($_.StartMode -ne "Disabled") )}
         
        if($WinServices)
                {   
					foreach ($srvc in $WinServices)	
						{
							$service = $srvc.DisplayName
							$svc = $srvc.Name                          
					  
							Try 
									{
										Restart-Service -DisplayName $service -ErrorAction Continue; 
										Write-Host "`nRestarted $service on $Using:srv" -ForeGroundColor Green #-BackgroundColor Green  
										#Write-Color -text "`nRestarted " , "$service " , "on $Using:srv" -Color Green,Yellow,White
									}

							Catch 
									{
										Write-Host "`n`nService could not be restarted on "$srv":" -ForegroundColor Red;
										write-Host $_.Exception.Message				
									}                       
						}			
                }	
				
        else {}

Exit-PSSession		

} -AsJob -JobName RestartServz | Out-Null
}
wait-job -Name RestartServz -timeout $JobTimeout | Out-Null
Receive-Job -Name RestartServz
Remove-Job RestartServz | Out-Null
}
}



########################################
# Recycle SharePoint specific AppPools
########################################
function Recycle-AppPools
{
#This may need to be modified to match whichever configuration is being used. This should be assigned as a paramater above
$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

Write-Host "`n`n`nRecycling / Restarting any SharePoint AppPools...." -BackGroundColor White -ForeGroundColor Blue
Write-Host "`nPlease be patient...." -ForeGroundColor Yellow

$accounts = ConvertFrom-Csv $accounts 
$accounts | foreach {
$username = $_.Username #Pulled from the Username column

#Pulled from a global variable-function that programatically pulls the SharePoint servers. Can be done via array
Foreach ($server in $SPServers) 
{
	
Try {
        $SessionOption = New-PSSessionOption -IncludePortInSPN #Forces the port specified in the SPN
        Invoke-Command -ComputerName $server -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock { #Uses the session created above using the port in the SPN
        Import-Module WebAdministration
 
	        # Pulls the app pool list based on the credentials and whether it is stopped. 
	        $applicationPools = Get-ChildItem IIS:\AppPools | where { ($_.processModel.userName -eq "$Using:username") -and ($_.state -eq "Started") }

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
										        (Restart-WebAppPool -ErrorAction Continue -Name "$AppPool");
										        Write-Host "`nRecycled $AppPool on $Using:server" -ForegroundColor White -BackGroundColor Black								
									          }

								         Catch
									          {
										        Write-Host "`n`nNo-Go Recyle for $AppPool on $Using:server" -ForegroundColor Red;
										        write-Host $_.Exception.Message
									          }
						        }
				        }

			        Else {}

Exit-PSSession
} -AsJob -JobName RecyclePoolz | Out-Null
}
Catch { Write-Host "Could not invoke a remote command to $server!`n" -ForeGroundColor Red; write-Host $_.Exception.Message }
} 
wait-job -Name RecyclePoolz -timeout $JobTimeout | Out-Null
Receive-Job -Name RecyclePoolz
Remove-Job RecyclePoolz | Out-Null   
}
# Clears or resets variables
$accounts = $null 
}



###########################################################################
# (SharePoint) Updates Passwords SharePoint Managed Accounts
###########################################################################
function UpdateSPManagedAccounts
{
Write-Host "`n`n Starting process to change passwords in the SharePoint Farm itself!`n" -BackgroundColor White -ForeGroundColor Blue

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
			Write-Host “Changing SharePoint passwords for $username to $newpwd1” -ForegroundColor Blue -BackgroundColor Yellow;
			Set-SPManagedAccount -Identity $username -ExistingPassword $newpassword -Confirm:$false -UseExistingPassword:$true -ErrorAction Continue
		}

Catch 	{
			Write-Host "Error received updating the service account via Managed Accounts! Please review the logs and try again"
			write-Host $_.Exception.Message 
			pause
		}
} # End If
}
Write-Host "`n`nPausing for 1-minute to give the Timer Services time to process the changes across the farm..." -ForeGroundColor White
Start-Sleep 60
}
else 
	{
		Write-Host "This function must be launched from another function. Cancelling Action!" -ForeGroundColor Red;
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

Write-Host "`n`nChecking Account lockout status..." -ForeGroundColor Blue -BackGroundColor White
	
# Removes the domain and back-slash	from the username
Foreach ($user in $users)
		{

            $un = $user.username.split('\')[-1]
            $pw = $user.newpassword

                $locked = (Get-Aduser $un -Properties LockedOut).LockedOut
				
					if($locked) 
						{
							write-host "`n$un is Locked out!`n" -ForeGroundColor Red
							Write-Host "Attempting to unlock the account..." -ForeGroundColor Yellow
								Try 
										{
											Unlock-ADAccount -Identity $un -ErrorAction Continue;
											Write-Host "`nAccount $un is now unlocked!`n`n" -ForegroundColor Green						
										}
								Catch
										{
											Write-Host "Could not unlock the account. Verify and manually update the password in AD!`n`n" -BackGroundColor Yellow ForeGroundColor Red
											Pause
										}
								
						}
					
					else {write-host "`n$un is not locked out!`n" -foregroundcolor Green}
		}
}



###########################################################
# Updates Passwords in AD based on the $accounts variable
###########################################################
function UpdateAD
{

# Imports AD functionality
Import-Module ActiveDirectory
write-host "`n`nAD module imported..."

# Required because pulling directly from using the 'Global' method fails every time
if($Global:accounts) {$accounts = $Global:accounts}

# Pulls in the specific accounts from the temp csv file to be changed
$users = ConvertFrom-Csv $accounts 

Write-Host "Starting AD password changes..." -ForeGroundColor Blue -BackGroundColor Yellow
	
# Changes the AD passwords after removing the domain and back-slash	
Foreach ($user in $users)
		{
            $un = $user.username.split('\')[-1]
            $pw = $user.newpassword

					Try {
							$dn = Get-aduser $un | select -ExpandProperty DistinguishedName 
							write-host "Changing passwords in AD for $un to $pw`n" -ForegroundColor DarkBlue -BackgroundColor DarkYellow
							Set-ADAccountPassword $dn -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $pw -Force) -ErrorAction Stop 
						}
			
		        Catch 	{
					        Write-Host "`n`nError changing passwords in AD. Manually change the passwords in ADUC and then continue with the process once completed." -ForeGroundColor red -BackGroundColor Yellow;
					        pause						
				        }		
		}
		
	Write-Host "`nWaiting for AD changes to Synchronize`n`n" -ForeGroundColor Yellow -BackGroundColor Red;
	Start-Sleep 30;
	#Pause
	#cls
}



### Acquires required accounts for SharePoint farm ###
function Get-Accounts
	{
		Write-Host "`n`nBuilding list of AD accounts...`n`n" -ForegroundColor Yellow
		if($Global:accounts)
			{$Global:accounts = $null}
		
		Start-Sleep 10
		
		$Global:accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	
	}

	
####################################################
# (SharePoint) Service Accounts Password Update
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
		Get-Accounts

		# Update Windows Services
		Set-WindowsServicesCreds

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

#Stop-Transcript #Stops the current log file process
					#(Get-Item –Path $Logfile).Encrypt() # Broken on Prod for some reason
#cipher /A $logfile #Encrypts the log file for the user running this script only. 
}
 
 
 ########################################
 # (SharePoint) Stop Timer Service ######
 ########################################
 function StopTimerServices
 {
	Write-Host "`n`nStopping and disabling the SharePoint Timer service!" -ForeGroundColor Yellow
		  foreach ($server in $SPServers) 
			{
				Try 
						{
							Set-Service -Name "SPTimerV4" -Status Stopped -StartupType Disabled -PassThru -ComputerName $server | Out-Null -ErrorAction Continue
							Write-Host "Timer Service Stopped and Disabled on $server" -ForeGroundColor Green
						}

				Catch 
						{
							Write-Host "`nCould not stop the Timer service on $server. Manually disable and stop it!" -ForeGroundColor Red;
							write-Host $_.Exception.Message
						}
			} 
} 
 
 
 
 
########################################
# (SharePoint) Start Timer Service #####
########################################
function StartTimerServices
{
Write-Host "`n`nRESTARTING TIMER SERVICE ON ALL OF THE SERVERS!" -ForegroundColor Yellow

foreach ($server in $SPServers) 
	{
		Try 
				{
					Set-Service -Name "SPTimerV4" -StartupType Automatic -Status Running -PassThru -ComputerName $server | Out-Null -ErrorAction Continue;
					Write-Host "Service Enabled and Started on $server" -ForeGroundColor Green     
				}

		Catch 
				{
					Write-Host "`n`nService could not be started and enabled on "$server":" -ForegroundColor Red;
					write-Host $_.Exception.Message
				
				}
	}
} 
 

 
#################################################################
######### Check and Start any Stopped Windows Services ##########
#################################################################

function Check-WindowsServices
{

#Get List of accounts to check for stopped services
$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

Write-Host "`n`n`nChecking for any Windows Services that are enabled but not running...." -BackGroundColor White -ForeGroundColor Blue
Write-Host "`nThis may take some time. Please be patient...." -ForeGroundColor Yellow

#Loops a list of user accounts to check on each server for stopped services
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$username = $_.Username

foreach ($srv in $SPServers)
    {

        #Write-Host "`n`n`n`nConnecting to $srv to check for stopped services using $username...`n" -ForegroundColor DarkGreen -BackgroundColor Cyan
        $SessionOption = New-PSSessionOption -IncludePortInSPN
        Invoke-Command -ComputerName $srv -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock {
       

        $WinServices = Get-CimInstance win32_service | Where {(($_.StartName -eq "$Using:username") -and ($_.State -ne "Running") -and ($_.StartMode -ne "Disabled") )}
     
    
        if($WinServices)
                {   

					foreach ($srvc in $WinServices)	
						{
							$service = $srvc.DisplayName
							$svc = $srvc.Name
					  
							Try 
									{
										Set-Service -Name "$svc" -StartupType Automatic -Status Running -PassThru | Out-Null -ErrorAction Continue;
										Write-Host "`nService $service Enabled and Started on $Using:srv" -ForeGroundColor Blue -BackgroundColor Yellow     
									}

							Catch 
									{
										Write-Host "`n`nService could not be started and enabled on "$srv":" -ForegroundColor Red;
										write-Host $_.Exception.Message				
									}                        
						}			
                }
				
        else {Write-Host "`nNo Services using $Using:username are stopped on $Using:srv" -ForeGroundColor Green}
Exit-PSSession		
} -AsJob -JobName CheckServz | Out-Null
}
wait-job -Name CheckServz -timeout $JobTimeout | Out-Null
Receive-Job -Name CheckServz
Remove-Job CheckServz | Out-Null
}
}
 

  
############################################################
# Manually Change passwords on SQL Server 
############################################################
function SQLChanges 
{
Write-Host "`n`nChanging SQL service account passwords!" -ForeGroundColor Blue -BackGroundColor White
Write-Host "`n Some of this process is manual so please pay attention!" -ForeGroundColor Blue -BackGroundColor White

#$ChangePasswords = Read-Host 'Are you sure you want to change the SQL Service Account passwords? Yes or No. (Default no) '  
$SQLaccounts = (Import-Csv $InputFile | Where {(($_ -match "mssql") -or ($_ -match "agent") -or ($_ -match "ssas") -and ($_ -match "Username") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	


# Imports AD functionality
Import-Module ActiveDirectory
write-host "`n`nAD module imported..."

# Pulls in the specific accounts from the temp csv file to be changed
$users = ConvertFrom-Csv $SQLaccounts

Write-Host "`n`nStarting AD password changes..." -ForeGroundColor Blue -BackGroundColor White
	
# Changes the AD passwords after removing the domain and back-slash	
Foreach ($user in $users)
		{
			
            $un = $user.username.split('\')[-1]
            $pw = $user.newpassword
			
			Try {
							$dn = Get-aduser $un | select -ExpandProperty DistinguishedName 
							write-host "Changing passwords in AD for $un to $pw" -ForegroundColor DarkBlue -BackgroundColor DarkYellow
							Set-ADAccountPassword $dn -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $pw -Force) -ErrorAction Stop 
						}
			
		    Catch 	
					{
					    Write-Host "`n`nError changing passwords in AD. Please change the $un password manually in AD and then press Enter to Continue`n" -ForeGroundColor Red;
					    Pause							
				    }		
		}		
		Write-Host `n `n'Change the passwords in SQL Server Configuration Manager on the SQL Server!' -ForeGroundColor Blue -BackGroundColor White;
		Write-Host `n'Press ENTER to continue after the passwords on the SQL server have been changed!' `n `n -ForegroundColor Yellow;
		pause
		
		Write-Host -NoNewLine `n'Passwords have been changed in the SQL server. ' `n -ForegroundColor Green
		#RestartSQL

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
#Get List of accounts
$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

Write-Host "`nPlease be patient....`n" 

#Loops a list of user accounts to check on each server 
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$username = $_.Username

foreach ($srv in $SPServers)
    {        
        #Write-Host "`nChecking for services on $srv`n" -ForegroundColor DarkGreen
        $SessionOption = New-PSSessionOption -IncludePortInSPN
        Invoke-Command -ComputerName $srv -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock {
        $WinServices = Get-CimInstance win32_service | Where {(($_.StartName -eq "$Using:username") -and ($_.StartMode -ne "Disabled") )}
         
        if($WinServices)
                {  
					Write-Host "`n$Using:srv is using the following:" -ForegroundColor Yellow
					foreach ($srvc in $WinServices)	
						{
							$service = $srvc.DisplayName
							$svc = $srvc.Name
							Write-Host "`nFound $service using the account $Using:username" -ForeGroundColor Green #-BackgroundColor Green     					                   
						}
						
						Write-Host "`n"						
                }	
				
        else {}

Exit-PSSession		

} -AsJob -JobName ListServz | Out-Null
}
wait-job -Name ListServz -Timeout 120 | Out-Null
Receive-Job -Name ListServz
Remove-Job ListServz | Out-Null
}
}


########################################
# List Affected AppPools
########################################
function List-AppPools
{
#This may need to be modified to match whichever configuration is being used. This should be assigned as a paramater above
$accounts = (Import-Csv $InputFile | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

#$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	


Write-Host "`nPlease be patient....`n" 

$accounts = ConvertFrom-Csv $accounts 
$accounts | foreach {
$username = $_.Username #Pulled from the 'Username' column

#Only uses the Web Servers
Foreach ($server in $SPServers | Where {$_ -match "WB"})
{

Try {
        $SessionOption = New-PSSessionOption -IncludePortInSPN #Forces the port specified in the SPN
        Invoke-Command -ComputerName $server -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock { #Uses the session created above using the port in the SPN
        Import-Module WebAdministration
 
		Try 
			{	
	        # Pulls the app pool list based on the credentials and whether it is stopped. 
	        $applicationPools = Get-ChildItem IIS:\AppPools | where { ($_.processModel.userName -eq "$Using:username") }# -and ($_.state -eq "Started") }
			}
			
		Catch 
			{
				Write-Host "No App Pools on &Using:server"
			}	
		
	  
			        if($applicationPools) # Only runs the below process if there are any app pools to run against (if not null)
				        { 	
							Write-Host "`n$Using:server is using the following:" -ForegroundColor Yellow
							
					        foreach($pool in $applicationPools)
					           {
                                    # Many powershell Commandlets and commands do not like variables pulled directly from outside of the invocation
							        $AppPool = $pool.name 				
									Write-Host "`nFound $AppPool using the account $Using:username" -ForegroundColor White -BackGroundColor Black								
						        }
								
								Write-Host "`n"
				        }

			        Else {}

Exit-PSSession
} -AsJob -JobName ListPoolz | Out-Null
}
Catch { Write-Host "Could not invoke a remote command to $server!`n" -ForeGroundColor Red; write-Host $_.Exception.Message }
} 
wait-job -Name ListPoolz -Timeout 120 | Out-Null
Receive-Job -Name ListPoolz
Remove-Job ListPoolz | Out-Null   
}
# Clears or resets variables
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
			1	{Get-Accounts; Set-WindowsServicesCreds; pause}
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
 Write-Host  "10.  Decrypt CSV containing passwords"
 Write-Host  "`n      The following task should only be used AFTER option 6 has been completed!" -ForegroundColor Yellow
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
 
[int]$Task = Read-Host "`n`nSelect a task to perform on this farm"

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
			10	{Cipher /D $InputFile; pause}
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