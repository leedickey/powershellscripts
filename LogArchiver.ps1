<#
.TITLE
Log Archiver and Cleaner

.PURPOSE
Cleans up Windows and IIS log files and moves them into a central location for
easy clean-up and maintenance

.VERSION
1.0 - 07/27/2017

#>



# Define amount of days of logs to keep
$Days = "60"

$BackupFolder = "D:\SA_Area\Log Archive"

# Location to store backed up system log files
$SystemBackupFolder = "D:\SA_Area\Log Archive\OS\System"    			# No Trailing slash \

# Location to store backed up system log files
$SecurityBackupFolder = "D:\SA_Area\Log Archive\OS\Security"    		# No Trailing slash \

# Location to store backed up system log files
$ApplicationBackupFolder = "D:\SA_Area\Log Archive\OS\Application"    	# No Trailing slash \

# IIS App Server Log locations
$IISAppLogLocation = "C:\inetpub\logs\LogFiles\W3SVC"					# No Trailing slash \

# IIS WFE Log Location 
$IISWFELogLocation = "w:\inetpub\logs\LogFiles\W3SVC"					# No Trailing slash \


Start-Transcript -Path "C:\allowed\scripts\LogArchive_Log.txt"


# Check for existence of backup folders and creates them if not.
If (!(Test-Path $ApplicationBackupFolder)) 
{	Try
		{
            New-Item $ApplicationBackupFolder -Type Directory -Force -ErrorAction Stop 
            $Success += "Created $ApplicationBackupFolder `n"
        }
	Catch
		{	
			$ApplicationBackupFolder
			$ErrorMsg += $_.Exception.Message
            $ErrorMsg
            Stop-Transcript
		}
}
		
If (!(Test-Path $SecurityBackupFolder))
{
	Try
		{
            New-Item $SecurityBackupFolder -Type Directory -Force -ErrorAction Stop
            $Success += "Created $SecurityBackupFolder `n"    
        }		
	Catch
		{
			$SecurityBackupFolder
			$ErrorMsg += $_.Exception.Message
            $ErrorMsg
            Stop-Transcript
		}
}
	
If (!(Test-Path $SystemBackupFolder)) 
{
	Try
		{
            New-Item $SystemBackupFolder -Type Directory -Force -ErrorAction Stop
            $Success += "Created $SystemBackupFolder `n"  
        } 
	Catch
		{
			$SystemBackupFolder
			$ErrorMsg += $_.Exception.Message	
            $ErrorMsg
            Stop-Transcript	
		}
}	




# Compresses the $BackupFolder and all subfolders if not already
cmd /c Compact /S:$BackupFolder /C


#----- Set the naming convention of the archive files -----#
$LogDate = Get-Date -f "yyyy-MM-dd-HH-mm-ss" #Do not modify this
$SecurityFileName = "Security $LogDate.evtx"
$SystemFileName = "System $LogDate.evtx"
$ApplicationFileName = "Application $LogDate.evtx"

# Computer running this script
$WhoAmI = $env:ComputerName


# Move automatic archived logs into the archive folder if they exist
$AutoArchivedLogs = Get-ChildItem -Path "C:\Windows\System32\winevt\Logs\Archive*"
foreach ($archived in $AutoArchivedLogs)
{
	Try
		{
			Move-Item "$archived" $BackupFolder -ErrorAction Continue
            $Success += "Moved the automatically created archived log file named ""$archived"" `n"
		}
    Catch
        {
            $ErrorMsg += $_.Exception.Message	
            $ErrorMsg
        }

}

#Archive System logs
wevtutil cl System /bu:$SystemBackupFolder\$SystemFileName

#Archive Security Logs
wevtutil cl System /bu:$SecurityBackupFolder\$SecurityFileName

#Archive Application logs
wevtutil cl System /bu:$ApplicationBackupFolder\$ApplicationFileName
	

	
#*****************************************************
#************* Log clean up tasks ********************	
#*****************************************************

# Sets the number of days from today's date 
$Limit = (Get-Date).AddDays(-$Days)	

# Clean up Application logs
Try
    {
        Get-ChildItem -Path $ApplicationBackupFolder -Force *.evtx -Recurse | Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -le $Limit } | Remove-Item -Force -ErrorAction Continue
        $Success += "Deleted logs older than 60-days in ""$ApplicationBackupFolder"" `n"
    }

Catch
  {
         $ErrorMsg += $_.Exception.Message	
         $ErrorMsg
  }


# Clean up Security logs
Try
    {
        Get-ChildItem -Path $SecurityBackupFolder -Force *.evtx -Recurse | Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -le $Limit } | Remove-Item -Force -ErrorAction Continue
        $Success += "Deleted logs older than 60-days in ""$SecurityBackupFolder"" `n"
    }
Catch
  {
        $ErrorMsg += $_.Exception.Message
        $ErrorMsg	
  }


# Clean up System logs
Try
    {
        Get-ChildItem -Path $SystemBackupFolder -Force *.evtx -Recurse | Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -le $Limit } | Remove-Item -Force -ErrorAction Continue
        $Success += "Deleted logs older than 60-days in ""$SystemBackupFolder"" `n"
    }
Catch
  {
         $ErrorMsg += $_.Exception.Message	
         $ErrorMsg
  }


# Clean up Archived Windows logs
Try
    {
        Get-ChildItem -Path $BackupFolder -Force *.evtx | Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -le $Limit } | Remove-Item -Force -ErrorAction Continue
        $Success += "Deleted auto archived logs older than 60-days in ""$BackupFolder"" `n"
    }
 Catch
  {
         $ErrorMsg += $_.Exception.Message	
         $ErrorMsg
  }



# Clean up IIS Logs on Application Servers
if (Test-Path $IISAppLogLocation)
{   Try
        {
	        $AppGet = Get-ChildItem -Path $IISAppLogLocation -Recurse -Force *.log | Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -le $Limit } 
                
                foreach ($teg in $AppGet)
                    {
                        Remove-item $teg.FullName -recurse -Force -ErrorAction Continue
                        #$Success += "Cleaned up IIS logs at ""$IISAppLogLocation"" `n"
                    }    
		}
    Catch
        {
             $ErrorMsg += $_.Exception.Message
             $ErrorMsg	
        }
}


# Clean up IIS logs on Web Servers
if (Test-Path $IISWFELogLocation)
{   Try
        {
    	    $WFEGet = Get-ChildItem -Path $IISWFELogLocation -Recurse -Force *.log | Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -le $Limit } 

                foreach ($get in $WFEGet)
                    {
                        Remove-item $get.FullName -recurse -Force -ErrorAction Continue
                        #$Success += "Cleaned up IIS logs at ""$IISWFELogLocation"" `n"
                    }
        }
    Catch
        {
            $ErrorMsg += $_.Exception.Message	
            $ErrorMsg
        }
}
$Success

Stop-Transcript
