<#
.SYNOPSIS
Performs multiple Password tasks for the system servers via a menu.
.DESCRIPTION
Changes account passwords using the provided CSV (inputfile), restarts the servers and other tasks.
.EXAMPLE
.\PasswordChangeTasks.ps1 -inputFile "yourfile.csv" 
.FEATURES
		-	Fully menu driven. Just run the script as an administrator
		- 	Check against list of accounts to confirm if the AD accounts are locked and will attempt to unlock them for you
		-	Check against list of credentials to determine if App Pools using those credentials are running and will try to start them.
		-	Check against list of credentials to determine if Windows Services using those credentials are running and will try to start them
		-	Will change passwords in Active Directory if required csv file is provided (See Parameters)
		-	Will change passwords for App Pools and Windows Services on each server using required csv file (See Parameters)
		- 	Will restart running Windows Services associated to the service accounts listed in csv file	
		-	Will recycle / restart IIS AppPools associated to the service accounts listed in the csv file
.REQUIREMENTS
		-	Powershell 3.0 or higher
		-	WinRM must be enabled and remote Powershell must also be enabled
		-	Service Principle Names (SPNs) may be required for your systems depending on the environment
			-	Special SPNs were required for mine specifying the Powershell port (5985 and 5986 (SSL))
				Example: 	setspn -s HTTP/Server-Short-Name-001:5985 Server-Account-Name-01
							setspn -s HTTP/Server-Long-Name-001-Is-Very-Long-:5985 Server-Account-Name-01
	
	
.NOTES
Author: Lee Dickey 
Date: 14 June 2017
Version: 2.0

V 2.0 06/14/2017
	
	2.0 
		- Text clean-up
		- Added parrallel processing for many of the functions to spead up password changes
		- Added function to restart currently running Windows Services 
		- Added function to recycle / restart App Pools
		
		
V 1.0 04/27/2017:

	1.0
		- Initial Release. Password changes for IIS App Pools and Windows Services across the enclave. It can update AD for you as well. Also reboots the enclave and 
			can restart services and recycle app pools
		
#>


### Parameters that should only be changed if absolutely necessary ###
# Needs to be cleaned up. Not needed as Parameters.
[cmdletbinding()]
param(
[string] $Global:InputFile = "c:\Allowed\Scripts\accounts.csv"
	)
	
	
########################################################	
###### LIST OF CUSTOMIZABLE SETTINGS AND VARIABLES
########################################################

## A text file listing the servers in the environment
$Global:serverlist = "C:\allowed\scripts\serverlist.txt"

## A text file listing of any SQL or database servers
$Global:SQLServers = "C:\allowed\scripts\SQLserverlist"

## Location and name of the log file
$Global:Logfile = "c:\Allowed\Scripts\Log.log"





################################################## 
# Check for Admin Privileges
##################################################
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!`n(Right-Click Powershell Icon, Click 'Run as Administrator')"
    Break
} ###############################################



##################################################################
# Getting the server list
##################################################################
function GetServerList
{
# Get list of servers from a predefined list of servers and puts the list into memory as a CSV formatted variable
#$Global:AppServers = Get-Content -Patch $Appserverlist | ConvertTo-CSV -NoTypeInformation | Select-Object -skip 1 | % {$_ -replace '"',''}) | Out-String
$Global:Servers = Get-Content -Path $serverlist
$Global:DBServers = Get-Content -Path $SQLserverlist
}
GetServerList





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
foreach ($system in $Servers) 
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




###########################################################
# Restart all of the servers (not DB)
###########################################################
function RestartServers
{
write-Host "`n`n`nServers (Not SQL) be restarted!" -ForegroundColor Green
Write-Host "Type 'Yes' and press enter to restart all servers (not DB server)!" -ForegroundColor DarkYellow
$RestartServers = Read-Host 'Yes or No (Default Yes)  >>'  

if (($RestartServers -eq 'Yes') -or ($RestartServers -eq "y"))
{
# Rebuilds the server list excluding the current logged in system to avoid rebooting the system you are currently using
$Servers = $Servers | Where-Object {$_ -ne $env:computername}
foreach ($server in $Servers) {
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
Write-Host "`nAfter this system reboots, give all processes and services 5 to 10 minutes to start up before you continue." -ForegroundColor Red;
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
		Write-Host " `n `n Exited without restarting the servers. This may be required at a later time." -ForegroundColor Red
Exit
}
}



#####################################
# Prompt to restart SQL Server
#####################################
function RestartSQL
{
cls
Write-Host "Type Yes to restart the database server $DBServers" -ForegroundColor Red
Write-Host "`nType 'Yes' or press enter in order to restart the server" -ForegroundColor Green
$RestartDB = Read-Host ' Restart SQL Servers? Yes or No. (Default No) '  
if (($RestartDB -eq 'Yes') -or ($RestartDB -eq 'y'))
	{		
		Try {
				#LockSPSites
				Restart-Computer -ComputerName $DBServers -Force;# -ErrorAction Stop;
				Write-Host "`n`nRestarting the database server $DBServers....`n"  -ForeGroundColor Red;
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

Foreach ($server in $Servers)
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
	Wait-Job -Name UpdateAppPoolz -Timeout 60 | out-null
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

Foreach ($server in $Servers) 
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
wait-job -Name StartPoolz -Timeout 60 | Out-Null
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

Foreach ($server in $Servers)
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
} # End of Foreach ($server in $Servers)
wait-job -Name SetServCredz -Timeout 60 | Out-Null
Receive-Job -Name SetServCredz
Remove-Job SetServCredz | Out-Null
} # End of $passwords | foreach


} # End of function Set-WindowsServicesCreds




###########################################################
# Checking if Accounts locked out in AD
###########################################################
function Check-ADLockOuts
{
$ADaccounts = (Import-Csv $InputFile | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	
$users = ConvertFrom-Csv $ADaccounts 

Write-Host "`n`nChecking Account lockout status..." -ForeGroundColor Red -BackGroundColor Yellow
	
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

Write-Host "Starting AD password changes..." -ForeGroundColor Red -BackGroundColor Yellow
	
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



### Acquires required accounts ###
function Get-Accounts
	{
		Write-Host "`n`nBuilding list of AD accounts...`n`n" -ForegroundColor Yellow
		if($Global:accounts)
			{$Global:accounts = $null}
		
		Start-Sleep 10
		
#		$Global:accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	
		$Global:accounts = (Import-Csv $InputFile | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	
	}

	
####################################################
# Service Accounts Password Changes
####################################################
function Change-ServiceAccountPasswords #This is the primary function for  Password changes 
{

### Checks for any running Logging / Transcripts and kills them before starting a new one for this script
try		{stop-transcript|out-null}
catch 	[System.InvalidOperationException]{}

#Starts a new log file
#Start-Transcript -Path $Logfile 

# Used for other functions to confirm they are initiated from this primary function
$Global:FunctionCheck = "yes"

Write-Host `n `n `n
Write-Host "This will change the service account passwords." -ForegroundColor Blue -BackGroundColor White
Write-Host "`nDoing this will cause downtime with the system!" -ForegroundColor Blue -BackGroundColor White
Write-Host "`nAre you sure you want to perform this task??" -ForegroundColor Green
$ChangePasswords = Read-Host ' Start the Service Account password change process? Yes or No. (Default no) '  
if (($ChangePasswords -eq 'yes') -or ($ChangePasswords -eq 'y')) 
	{
	
		#Verifies that all servers can be access with 'invoke-command'
		#WinRMVerify

		# Creates CSV formated variable to use for determining which accounts get their passwords updated
		# Does not include the SQL and Agent accounts
		Get-Accounts

		# Updates AD
		UpdateAD

		#Update SQL accounts
		SQLChanges

		#Re-acquire accounts for main system
		Get-Accounts

		# Update Windows Services
		Set-WindowsServicesCreds

		# Updates the App Pools
		Update_AppPools

		# Clears or resets variables
		$accounts = $null
		$FunctionCheck = "no"

		# Restarts the farm
		RestartServers
	}

else 
	{
		Write-Host "`n`nPassword change process cancelled!" -ForeGroundColor Red; 
	}

#Stop-Transcript #Stops the current log file process
					#(Get-Item –Path $Logfile).Encrypt() # Broken on Prod for some reason
#cipher /E $logfile #Encrypts the log file for the user running this script only. 
}
 
 
 
########################################
# Stop specific service(s) ######
########################################
function StopServices
{
#Get List of accounts to check for services to be stopped
$accounts = (Import-Csv $InputFile | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

#Loops a list of user accounts to check on each server for services to stop
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$username = $_.Username

foreach ($srv in $Servers)
    {
        Write-Host "`n`n`n`nConnecting to $srv to check for services using $username...`n" -ForegroundColor DarkGreen -BackgroundColor Cyan
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
										Set-Service -Name "$svc" -StartupType Disabled -Status Stopped -PassThru | Out-Null -ErrorAction Continue;
										Write-Host "Service $service -- Stopped and Disabled" -ForeGroundColor Green     
									}

							Catch 
									{
										Write-Host "`n`nService could not be Stopped and Disabled on "$srv":" -ForegroundColor Red;
										write-Host $_.Exception.Message				
									}                        
						}			
                }
				
        else {Write-Host "No Services to stop on this system!" -ForeGroundColor Yellow}
}}}	
} 
 
  
 
#################################################################
######### Check and Start any Stopped Windows Services ##########
#################################################################

function Check-WindowsServices
{
#Get List of accounts to check for stopped services
$accounts = (Import-Csv $InputFile | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	# | Where {(($_ -match "spfarm") -or ($_ -match "claim") -and ($_ -match "UserName"))}

#Loops a list of user accounts to check on each server for stopped services
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$username = $_.Username

foreach ($srv in $Servers)
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
wait-job -Name CheckServz -Timeout 60 | Out-Null
Receive-Job -Name CheckServz
Remove-Job CheckServz | Out-Null
}
}

 
  
############################################################
# Manually Change passwords on SQL Server 
############################################################
function SQLChanges 
{
Write-Host "`n`nChanging SQL service account passwords!" -ForeGroundColor Red -BackGroundColor Yellow
Write-Host "`n Some of this process is manual so please pay attention!" -ForegroundColor Red

#$ChangePasswords = Read-Host 'Are you sure you want to change the SQL Service Account passwords? Yes or No. (Default no) '  
$SQLaccounts = (Import-Csv $InputFile | Where {(($_ -match "mssql") -or ($_ -match "agent") -or ($_ -match "ssas") -and ($_ -match "Username") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	


# Imports AD functionality
Import-Module ActiveDirectory
write-host "`n`nAD module imported..."

# Pulls in the specific accounts from the temp csv file to be changed
$users = ConvertFrom-Csv $SQLaccounts

Write-Host "`n`nStarting AD password changes..." -ForeGroundColor Red -BackGroundColor Yellow
	
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
		Write-Host `n `n'Change the passwords in SQL Server Configuration Manager on the SQL Server!' -ForegroundColor Green;
		Write-Host `n'Press ENTER to continue after the passwords on the SQL server have been changed!' `n `n -ForegroundColor Red;
		pause
		
		Write-Host -NoNewLine `n'Passwords have been changed in the SQL server. ' `n -ForegroundColor Green
		#RestartSQL

	}



#################################################################
######### Start Previously stopped and disabled services ########
#################################################################

function Start-StoppedDisabledServices
{

#Get List of accounts to check for stopped services
$accounts = (Import-Csv $InputFile | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	# | Where {(($_ -match "spfarm") -or ($_ -match "claim") -and ($_ -match "UserName"))}

#Loops a list of user accounts to check on each server for stopped services
$passwords = ConvertFrom-Csv $accounts # Acquired from parent function
$passwords | foreach {
$username = $_.Username

foreach ($srv in $Servers)
    {

        #Write-Host "`n`n`n`nConnecting to $srv to check for stopped services using $username...`n" -ForegroundColor DarkGreen -BackgroundColor Cyan
        $SessionOption = New-PSSessionOption -IncludePortInSPN
        Invoke-Command -ComputerName $srv -SessionOption $SessionOption -ErrorAction Stop -ScriptBlock {
       

        $WinServices = Get-CimInstance win32_service | Where {(($_.StartName -eq "$Using:username") -and ($_.State -ne "Running") -and ($_.StartMode -eq "Disabled") )}
     
    
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
wait-job -Name CheckServz -Timeout 60 | Out-Null
Receive-Job -Name CheckServz
Remove-Job CheckServz | Out-Null
}
}


#########################################
# Restart Windows Services
#########################################
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

foreach ($srv in $Servers)
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
wait-job -Name RestartServz -Timeout 120 | Out-Null
Receive-Job -Name RestartServz
Remove-Job RestartServz | Out-Null
}
}



########################################
# Recycle  specific AppPools
########################################
function Recycle-AppPools
{
#This may need to be modified to match whichever configuration is being used. This should be assigned as a paramater above
$accounts = (Import-Csv $InputFile | Where {(($_ -notmatch "mssql") -and ($_ -notmatch "agent") -and ($_ -notmatch "ssas") )} | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''}) | Out-String	

Write-Host "`n`n`nRecycling / Restarting any AppPools...." -BackGroundColor White -ForeGroundColor Blue
Write-Host "`nPlease be patient...." -ForeGroundColor Yellow

$accounts = ConvertFrom-Csv $accounts 
$accounts | foreach {
$username = $_.Username #Pulled from the Username column

Foreach ($server in $Servers) 
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
wait-job -Name RecyclePoolz -Timeout 120 | Out-Null
Receive-Job -Name RecyclePoolz
Remove-Job RecyclePoolz | Out-Null   
}
# Clears or resets variables
$accounts = $null 
}



####################################################################
# Select a desired task to perform on farm
####################################################################
 do {
 
 [int]$Task = 0
while ($Task -lt 1 -or $Task -gt 12)  {
cls
Write-Host  "`n#####  TROUBLE-SHOOTING TASKS  #####" -ForegroundColor Black -BackgroundColor White
Write-Host  "1.   Verify Remote Connectivity"
Write-Host  "2.   Check if Accounts Locked"
Write-Host  "3.   Start any Application Pools that have stopped" 
Write-Host  "4.   Start any Windows Services that have stopped"
  
Write-Host  "`n#####  PASSWORD CHANGE TASKS  #####" -ForegroundColor Black -BackgroundColor White
Write-Host  "5.   Change Service Account Passwords"
  
Write-Host  "`n#####  SYSTEM RESTART OPTIONS  #####" -ForegroundColor Black -BackgroundColor White
Write-Host  "6.   Restart (Not SQL) Servers"
Write-Host  "7.   Restart SQL Server(s)"
 
Write-Host  "`n#####  MAINTENANCE TASKS  #####" -ForegroundColor Black -BackgroundColor White
Write-Host  "8.   Stop & Disable Services using service accounts on all servers"
Write-Host  "9.   Start previously stopped and disabled Services on all servers"
Write-Host  "10.  Restart running Windows Services" 
Write-Host  "11.  Recycle all system specific AppPools in IIS" 
 
Write-Host "`n12.  Exit this script" -ForeGroundColor Yellow
 
[int]$Task = Read-Host "`n`nSelect a task to perform on this farm"

switch($Task)
		{	
			1	{WinRMVerify; pause}
			2	{Check-ADLockOuts; pause}
			3	{Start-AppPools; pause}
			4	{Check-WindowsServices; pause}
			5	{Change-ServiceAccountPasswords; pause}
			6	{RestartServers}
			7	{RestartSQL; pause}
			8	{StopServices; pause}
			9	{Start-StoppedDisabledServices; pause}
			10	{Restart-WindowsServices; pause}
			11	{Recycle-AppPools; pause}
			12 	{exit}		
			
			default	{Write-Host "Nothing Selected"}			
		}
	}
} While ($Task -ne 12)

