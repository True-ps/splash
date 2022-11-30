<#
This script can be ran in a few different ways:
1. Without any parameters - this will install Splashtop if it is not installed
2. With the "install" parameter - this will attempt to upgrade Splashtop if already installed, or install it missing. A deployment code can be used.
3. With the "uninstall" parameter - this will uninstall Splashtop
4. With the "reinstall" parameter - This will uninstall then reinstall Splashtop. A deployment code can be used.
NOTE: They deployment code must be the second parameter passed. I.e. install xxxxxxxxxxxxxxx
Another NOTE: Unless supported by the developer of the script(me), any attempts at running the script with just the deployment code as parameter will fail.

I will do my best to maintain the Version of Splashtop that this script deploys, as well as update the syntax.
#>

<#setting script parameters#>
$splash = "Splashtop Streamer"
$random = Get-Random
$order = $args[0]
$key = $args[1] 
import-module Bitstransfer

#$splashDown = "https://my.splashtop.com/csrs/win"#<-----here is where you need to paste the new link!!!****
$splashDown = "https://redirect.splashtop.com/srs/win?"

$splashexecDir = "c:\splashtemp"

if ((Test-Path $splashexecDir) -eq $false)
{
New-Item $splashexecDir -ItemType "directory" -Force
}


$splashTemp = "C:\splashTemp\$random.exe";

$splashEXE = "C:\Program Files (x86)\Splashtop\Splashtop Remote\Server\SRServer.exe"

$hostname = hostname

$ip = (Get-WmiObject -Class Win32_NetworkAdapterConfiguration | Where-Object { $_.DefaultIPGateway -ne $null }).IPAddress | Select-Object -First 1

if($splashRegVer = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Splashtop Inc.\Splashtop Remote Server\" -Name Version -ErrorAction SilentlyContinue| Select-Object Version ){
$splashver = $splashRegver.version.Split("=")}
else{Write-Host -ForegroundColor Red "$splash is not installed"}

#the below commented syntax queries the WMI repository and can take a while to complete. 
#you can replace get-wmiobject with get-ciminstance. CIM is 700ms faster on an SSD.
<#if ($splashON = Get-WmiObject Win32_Product | Where-Object { $_.Name -like "Splashtop streamer" } | Select-Object Name, version)
{
[string]$splashName = $splashON.Name.Split("=")
	
[string]$splashAppVer = $splashON.Version.Split("=")

}#>

#creating eventlog definitions
$logFileExists = [System.Diagnostics.EventLog]::SourceExists("Streamer");
if (-not $logFileExists)
{New-EventLog -LogName Application -Source "Streamer"}

$eventlogvalues= @{
LogName = 'Application' 
Source = 'Streamer'
}

$errors = @{
EntryType = "Error"
EventID = 818
Message = "$splash was removed from $hostname($ip). Installed version was $splashver"
}

$human_Error = @{
EntryType = "Error"
EventID = 666
Message = "$splash was not installed on $hostname($ip). Please read the deployment instructions!"
}

$warning =@{
EntryType = "Warning"
EventID = 817
Message = "$splash was reinstalled on $hostname($ip). Current versions is $splashver"
}

$info = @{
EntryType = "Information"
EventID = 816
Message = "$splash was installed on $hostname($ip). Current version is $splashver"
}
$human_Info =@{
EntryType = "Information"
EventID = 815
Message = "$Splash is already installed. Current version is $splashver" 
}


function uninstall
{ 
$uninstallSplash = Get-WmiObject win32_product | Where-Object Name -Like "Splashtop Streamer" | Invoke-WmiMethod -Name Uninstall

[string[]]$splashProc = "streamer", "srserver"
foreach($proc in $splashProc)
{
if ($_ProCtrl = Get-Process $proc -ErrorAction SilentlyContinue)
			{
				if ($_ProCtrl.ProcessName -eq $proc)
				{
					Write-Host "Attempting to kill the $proc process"
					try
					{
						$_ProCtrl.Kill()
						$_ProCtrl.WaitForExit()
                        Write-Host "$proc is dead!"
					}
					catch {"I was unable to terminate the $proc process" }
				}
			}
			else { Write-Host "Process $proc not found!" }
Write-EventLog @eventlogValues @errors

}
    
}
function Install
{
	
	# Download the file and execute it
	
	#$download = Start-Bitstransfer $splashDown $splashTemp
	$error.clear()
	try{Start-Bitstransfer $splashDown $splashTemp}
	catch{"Start-Bitstransfer failed, or something! Ups!"}
    if ($error)
	{
	(New-Object System.Net.WebClient).DownloadFile([string]$splashDown , [string]$splashTemp)
	}
	
	
	Start-Process $splashTemp -ArgumentList prevercheck, /s, /i, confirm_d=0, hidewindow=1, dcode=$key -Wait
	
	if ([string]::IsNullOrEmpty($splashver))
	{

		#cleanup
		remove-item -recurse $splashexecDir -Force
	}

Write-EventLog @eventlogvalues @info
}

function _serviceDispatch
{
	
	[string[]]$_services = "SplashtopRemoteService"
	
	foreach ($_service in $_services)
	{
		start-sleep -Seconds 2
		
		$_svcControl = Get-Service $_service -ErrorAction SilentlyContinue
		
		if ($_svcControl)
		{
			
			if ($_svcControl.Status -eq "Stopped")
			{
				Write-Output "Starting the $_service Service..."
				$_svcControl.Start()
				$_svcControl.WaitForStatus("Running")
				Write-Output "$_service is Running"
			}
			else { Write-Host "The $_service is already running!" }
		}
		else
		{
			Write-Host "$_service not found! $_service is not installed or partially installed. Please re-run this script with the install parameter. Program will exit!"
			break;
		}
	}
	
}

if ((Test-Path $splashEXE) -eq $false)
{
	
	    Write-Output "`n$splashExe not found!";
	    $timings = Measure-Command -Expression { install }
	    $reportTime = $timings.Seconds
	    Write-output "You have successfully installed $splashName in just $reporttime seconds on $hostname with IP $ip!`n`nYour new Streamer version is:" $splashVer "`n"
	    _serviceDispatch
}

else
{
	if (($order -eq "install" -and [string]::IsNullOrEmpty($key)) -or ($order -eq "install" -and (-not[string]::IsNullOrEmpty($key))))
	{
		Write-Output "You have run this script with the $order parameter. You are upgrading $splash from version" $splashVer
		$timings = Measure-Command -Expression { install }
		$reportTime = $timings.Seconds
        #i don't know how to get the same value twice during the runtime and display it as it changes, without re-running the whole command.
        $splashVerNEW = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Splashtop Inc.\Splashtop Remote Server\" -Name Version | Select-Object Version
		Write-output "You have successfully installed $splash in just $reporttime seconds!`n`nYour new Streamer version is:" $splashVerNEW.Version"`n"
		_serviceDispatch
	}
	elseif ($order -eq "uninstall")
	{
		uninstall
		write-output "You have successfully uninstalled $splash from $hostname($ip). Thank you for your trust in us!"
	}
	elseif (($order -eq "reinstall" -and [string]::IsNullOrEmpty($key)) -or ($order -eq "reinstall" -and (-not[string]::IsNullOrEmpty($key))))
	{
        write-host "Warning! You have chosen to reinstall your $splash!"
		uninstall
        write-host "$splash uninstall process has successfully completed. "
		Install
        write-host "$splash has been reinstalled! Please wait a few minuntes before attempting to use the program!"
        _serviceDispatch
        Write-EventLog @eventlogValues @warning
	}
    elseif(-not[string]::IsNullOrEmpty($order) -and ($order -ne "reinstall" -and $order -ne "install" -and $order -ne "uninstall"))

    {
    Write-Output "One of the directives of this script is to NOT run it with just a deployment code.
    `nThe parameter you provided is $order and it does not match any of the accepted parameters."
    Write-Output "This script will now end. Please read the script directives and try again, this time using one of the accepted parameters"
    Write-EventLog @eventlogvalues @human_Error
    }
	
	else
	{
		Write-Output "$splash is already installed in $splashExe. The currently installed version is:"$splashver
		Write-Output "`nIf you would like to upgrade, please re-run this script with the `"install`" parameter"
		Write-output "`nTo Uninstall the $splash, please run the script with the`"uninstall`" parameter"
        Write-Output "`nTo reinstall $splash, please run the script with the `"reinstall`" parameter"
        Write-EventLog @eventLogValues @human_Info
	}
	
}
