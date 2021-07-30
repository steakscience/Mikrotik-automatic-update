# Script name: BackupAndUpdate
#
#----------SCRIPT INFORMATION---------------------------------------------------
#
# Script:  Mikrotik RouterOS automatic backup & update
# Version: 21.03.30
# Created: 07/08/2018
# Updated: 30/03/2021
# Author:  Alexander Tebiev
# Website: https://github.com/beeyev
# You can contact me by e-mail at tebiev@mail.com
#
# IMPORTANT!
# Minimum supported RouterOS version is v6.43.7
#
#----------MODIFY THIS SECTION AS NEEDED----------------------------------------
:local scriptMode "osupdate";

## Update channel. Possible values: stable, long-term, testing, development
:local updateChannel "stable";

## Install only patch versions of RouterOS updates.
## Works only if you set scriptMode to "osupdate"
## Means that new update will be installed only if MAJOR and MINOR version numbers remained the same as currently installed RouterOS.
## Example: v6.43.6 => major.minor.PATCH
## Script will send information if new version is greater than just patch.
:local installOnlyPatchUpdates	false;

##------------------------------------------------------------------------------------------##
#  !!!! DO NOT CHANGE ANYTHING BELOW THIS LINE, IF YOU ARE NOT SURE WHAT YOU ARE DOING !!!!  #
##------------------------------------------------------------------------------------------##

#Script messages prefix
:local SMP "Bkp&Upd:"

:log info "\r\n$SMP script \"Mikrotik RouterOS automatic backup & update\" started.";
:log info "$SMP Script Mode: $scriptMode;

#Check if proper identity name is set
if ([:len [/system identity get name]] = 0 or [/system identity get name] = "MikroTik") do={
	:log warning ("$SMP Please set identity name of your device (System -> Identity), keep it short and informative.");  
};

############### vvvvvvvvv GLOBALS vvvvvvvvv ###############
# Function converts standard mikrotik build versions to the number.
# Possible arguments: paramOsVer
# Example:
# :put [$buGlobalFuncGetOsVerNum paramOsVer=[/system routerboard get current-RouterOS]];
# result will be: 64301, because current RouterOS version is: 6.43.1
:global buGlobalFuncGetOsVerNum do={
	:local osVer $paramOsVer;
	:local osVerNum;
	:local osVerMicroPart;
	:local zro 0;
	:local tmp;
	
	# Replace word `beta` with dot
	:local isBetaPos [:tonum [:find $osVer "beta" 0]];
	:if ($isBetaPos > 1) do={
		:set osVer ([:pick $osVer 0 $isBetaPos] . "." . [:pick $osVer ($isBetaPos + 4) [:len $osVer]]);
	}
	
	:local dotPos1 [:find $osVer "." 0];

	:if ($dotPos1 > 0) do={ 

		# AA
		:set osVerNum  [:pick $osVer 0 $dotPos1];
		
		:local dotPos2 [:find $osVer "." $dotPos1];
				#Taking minor version, everything after first dot
		:if ([:len $dotPos2] = 0) 	do={:set tmp [:pick $osVer ($dotPos1+1) [:len $osVer]];}
		#Taking minor version, everything between first and second dots
		:if ($dotPos2 > 0) 			do={:set tmp [:pick $osVer ($dotPos1+1) $dotPos2];}
		
		# AA 0B
		:if ([:len $tmp] = 1) 	do={:set osVerNum "$osVerNum$zro$tmp";}
		# AA BB
		:if ([:len $tmp] = 2) 	do={:set osVerNum "$osVerNum$tmp";}
		
		:if ($dotPos2 > 0) do={ 
			:set tmp [:pick $osVer ($dotPos2+1) [:len $osVer]];
			# AA BB 0C
			:if ([:len $tmp] = 1) do={:set osVerNum "$osVerNum$zro$tmp";}
			# AA BB CC
			:if ([:len $tmp] = 2) do={:set osVerNum "$osVerNum$tmp";}
		} else={
			# AA BB 00
			:set osVerNum "$osVerNum$zro$zro";
		}
	} else={
		# AA 00 00
		:set osVerNum "$osVer$zro$zro$zro$zro";
	}

	:return $osVerNum;
}

:global buGlobalVarUpdateStep;
############### ^^^^^^^^^ GLOBALS ^^^^^^^^^ ###############

#Current date time in format: 2020jan15-221324 
:local dateTime ([:pick [/system clock get date] 7 11] . [:pick [/system clock get date] 0 3] . [:pick [/system clock get date] 4 6] . "-" . [:pick [/system clock get time] 0 2] . [:pick [/system clock get time] 3 5] . [:pick [/system clock get time] 6 8]);

:local deviceOsVerInst 			[/system package update get installed-version];
:local deviceOsVerInstNum 		[$buGlobalFuncGetOsVerNum paramOsVer=$deviceOsVerInst];
:local deviceOsVerAvail 		"";
:local deviceOsVerAvailNum 		0;
:local deviceRbModel			[/system routerboard get model];
:local deviceRbSerialNumber 	[/system routerboard get serial-number];
:local deviceRbCurrentFw 		[/system routerboard get current-firmware];
:local deviceRbUpgradeFw 		[/system routerboard get upgrade-firmware];
:local deviceIdentityName 		[/system identity get name];
:local deviceIdentityNameShort 	[:pick $deviceIdentityName 0 18]
:local deviceUpdateChannel 		[/system package update get channel];

:local isOsUpdateAvailable 	false;
:local isOsNeedsToBeUpdated	false;

:local updateStep $buGlobalVarUpdateStep;
:do {/system script environment remove buGlobalVarUpdateStep;} on-error={}
:if ([:len $updateStep] = 0) do={
	:set updateStep 1;
}


## 	STEP ONE: Checking for new RouterOs version
:if ($updateStep = 1) do={
	:log info ("$SMP Performing the first step.");   

	# Checking for new RouterOS version
	if ($scriptMode = "osupdate" or $scriptMode = "osnotify") do={
		log info ("$SMP Checking for new RouterOS version. Current version is: $deviceOsVerInst");
		/system package update set channel=$updateChannel;
		/system package update check-for-updates;
		:delay 5s;
		:set deviceOsVerAvail [/system package update get latest-version];

		# If there is a problem getting information about available RouterOS from server
		:if ([:len $deviceOsVerAvail] = 0) do={
			:log warning ("$SMP There is a problem getting information about new RouterOS from server.");
		} else={
			#Get numeric version of OS
			:set deviceOsVerAvailNum [$buGlobalFuncGetOsVerNum paramOsVer=$deviceOsVerAvail];

			# Checking if OS on server is greater than installed one.
			:if ($deviceOsVerAvailNum > $deviceOsVerInstNum) do={
				:set isOsUpdateAvailable true;
				:log info ("$SMP New RouterOS is available! $deviceOsVerAvail");
			} else={
				:log info ("$SMP System is already up to date.");
			}
		};
	};

	# if new OS version is available to install
	if ($isOsUpdateAvailable = true) do={
		# if we need to initiate RouterOs update process
		if ($scriptMode = "osupdate") do={
			:set isOsNeedsToBeUpdated true;
			# if we need to install only patch updates
			:if ($installOnlyPatchUpdates = true) do={
				#Check if Major and Minor builds are the same.
				:if ([:pick $deviceOsVerInstNum 0 ([:len $deviceOsVerInstNum]-2)] = [:pick $deviceOsVerAvailNum 0 ([:len $deviceOsVerAvailNum]-2)]) do={
					:log info ("$SMP New patch version of RouterOS firmware is available.");   
				} else={
					:log info ("$SMP New major or minor version of RouterOS firmware is available. You need to update it manually.");
					:set isOsNeedsToBeUpdated false;
				}
			}

			#Check again, because this variable could be changed during checking for installing only patch updats
			if ($isOsNeedsToBeUpdated = true) do={
				:log info ("$SMP New RouterOS is going to be installed! v.$deviceOsVerInst -> v.$deviceOsVerAvail");
				#!! There is more code connected to this part and first step at the end of the script.
			}
		
		}
	}
}

## 	STEP TWO: (after first reboot) routerboard firmware upgrade
## 	steps 2 and 3 are fired only if script is set to automatically update device and if new RouterOs is available.
:if ($updateStep = 2) do={
	:log info ("$SMP Performing the second step.");   
	## RouterOS is the latest, let's check for upgraded routerboard firmware
	if ($deviceRbCurrentFw != $deviceRbUpgradeFw) do={
		:log info "$SMP Upgrading routerboard firmware from v.$deviceRbCurrentFw to v.$deviceRbUpgradeFw";
		## Start the upgrading process
		/system routerboard upgrade;
		## Wait until the upgrade is completed
		:delay 5s;
		:log info "$SMP routerboard upgrade process was completed, going to reboot in a moment!";
		## Set scheduled task to send final report on the next boot, task will be deleted when is is done. (That is why you should keep original script name)
		/system schedule add name=BKPUPD-FINAL-REPORT-ON-NEXT-BOOT on-event=":delay 5s; /system scheduler remove BKPUPD-FINAL-REPORT-ON-NEXT-BOOT; :global buGlobalVarUpdateStep 3; :delay 10s; /system script run BackupAndUpdate;" start-time=startup interval=0;
		## Reboot system to boot with new firmware
		/system reboot;
	} else={
		:log info "$SMP It appers that your routerboard is already up to date, skipping this step.";
		:set updateStep 3;
	};
}

## 	STEP THREE: Last step (after second reboot) sending final report
## 	steps 2 and 3 are fired only if script is set to automatically update device and if new RouterOs is available.
:if ($updateStep = 3) do={
	:log info ("$SMP Performing the third step.");   
	:log info "Bkp&Upd: RouterOS and routerboard upgrade process was completed. New RouterOS version: v.$deviceOsVerInst, routerboard firmware: v.$deviceRbCurrentFw.";
	## Small delay in case mikrotik needs some time to initialize connections
}

# Remove functions from global environment to keep it fresh and clean.
:do {/system script environment remove buGlobalFuncGetOsVerNum;} on-error={}

# Fire RouterOs update process
if ($isOsNeedsToBeUpdated = true) do={

	## Set scheduled task to upgrade routerboard firmware on the next boot, task will be deleted when upgrade is done. (That is why you should keep original script name)
	/system schedule add name=BKPUPD-UPGRADE-ON-NEXT-BOOT on-event=":delay 5s; /system scheduler remove BKPUPD-UPGRADE-ON-NEXT-BOOT; :global buGlobalVarUpdateStep 2; :delay 10s; /system script run BackupAndUpdate;" start-time=startup interval=0;
   
   :log info "$SMP everything is ready to install new RouterOS, going to reboot in a moment!"
	## command is reincarnation of the "upgrade" command - doing exactly the same but under a different name
	/system package update install;
}

:log info "$SMP script \"Mikrotik RouterOS automatic backup & update\" completed it's job.\r\n";