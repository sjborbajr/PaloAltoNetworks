Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#Install-Module 'pan-power' -Scope CurrentUser
Import-Module pan-power

#Gather Data
$Devices = (Invoke-PANOperation -Command "<show><devices><connected></connected></devices></show>").result.devices.entry
$Devices = $Devices | Out-GridView -OutputMode Multiple
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  $HA = Invoke-PANOperation -SkipCertificateCheck -Command ("<show><high-availability><state/></high-availability></show>&target="+$Devices[$ix].serial)
  Add-Member -InputObject $Devices[$ix] -NotePropertyMembers @{
    'ha-running-sync'=$HA.result.group.'running-sync'
    'ha-type'=$HA.result.group.mode
    'ha-state'=$HA.result.group.'local-info'.state
    'ha1-encrypt-enable'=$HA.result.group.'local-info'.'ha1-encrypt-enable'
    'ha-priority'=$HA.result.group.'local-info'.priority
    'ha-preemptive'=$HA.result.group.'local-info'.preemptive
  }
}
$Version = "10.1.11-h1"

#Put it into lists
$Single = $Devices | ? { -not ($_.'ha-state') }
$Passive = $Devices | ? { $_.'ha-state' -eq 'passive' }
$Active = $Devices | ? { $_.'ha-state' -eq 'active' }

#Prepare for updates by syncing config and downloading software

##################################
#Sync from active to Passive for any out of sync devices
$Sync = $Active | ? { $_.'ha-running-sync' -eq 'not synchronized' }
#Sync HA Config
for ($ix = 0; $ix -lt $Sync.count; $ix++) {
  $Result = Invoke-PANOperation -Command "<request><high-availability><sync-to-remote><running-config></running-config></sync-to-remote></high-availability></request>" -Target $Sync[$ix].serial
  write-host ("Started sync on "+$Sync[$ix].hostname+": "+$Result.msg.line)
}
# end of sync section
##################################

##################################
#Check for software and download
#Remember to download base
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  $Result = Invoke-PANOperation -Command ("<request><system><software><check/></software></system></request>&target="+$Devices[$ix].serial)
  if ($Result.status -eq 'success') {
    if (($Result.result.'sw-updates'.versions.entry | ? {$_.version -eq $Version}).downloaded -ne "yes") {
      $Download = Invoke-PANOperation -Command ("<request><system><software><download><version>$Version</version></download></software></system></request>&target="+$Devices[$ix].serial)
      if ($Download.status -eq 'success') {
        Add-Member -Force -InputObject $Devices[$ix] -NotePropertyMembers @{
          'download-job-id'=$Download.result.job
        }
        write-host ("Started download on "+$Devices[$ix].hostname)
      } else {
        write-host ("Unable to download "+$Devices[$ix].hostname)
        $Download.result.outterxml
      }
    } else {
      write-host ("Install already downloaded on "+$Devices[$ix].hostname)
    }
  } else {
    write-host ("Unable check for software "+$Devices[$ix].hostname)
    $Result.result.outterxml
  }
}

#Check Status of download job
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  if ($Devices[$ix].'download-job-id') {
    $Result = Invoke-PANOperation -Command ("<show><jobs><id>"+$Devices[$ix].'download-job-id'+"</id></jobs></show>&target="+$Devices[$ix].serial)
    write-host ("Download status on "+$Devices[$ix].hostname+" is: "+$Result.result.job.status+" "+$Result.result.job.details.line)
  } else {
    write-host ("No Download Job on "+$Devices[$ix].hostname)
  }
}
# End download section
##################################


##################################
# Notes for actions on day of install
##################################
## Steps for Day of:
##  Reboot the Normall Passive Device
##  Update the normally Active Device to go passive
## -test through firewall-
##  Upgrade the normally Active Device and then reboot
##  Update the normally Active Device to go Active
## -test through firewall-
##  (?maybe wait two weeks?)
##  Upgrade the normally Passive Device and then reboot
##################################

##################################
#Reboot devices
#$Reboot = $Check_Devices
#$Reboot = $Passive | Out-GridView -OutputMode Multiple
for ($ix = 0; $ix -lt $Reboot.count; $ix++) {
  $HA = Invoke-PANOperation -SkipCertificateCheck -Command ("<show><high-availability><state/></high-availability></show>&target="+$Reboot[$ix].serial)
  if ($HA.result.group.'local-info'.state -ne 'passive') {
    $Response = Read-Host -Prompt ($Reboot[$ix].hostname+" is not passive, this may cause an outage, reboot anyhow? (y/n)?")
    if ($Response -eq 'y') {
      $do_reboot = $true
    } else {
      $do_reboot = $false
    }
  } else {
    $do_reboot = $true
  }
  if ($do_reboot) {
    $Result = Invoke-PANOperation -Command "<request><restart><system/></restart></request>" -Target $Reboot[$ix].serial
    Add-Member -Force -InputObject $Reboot[$ix] -NotePropertyMembers @{
      'reboot'=$result
    }
    $temp = "/c ping -t  "+$Reboot[$ix].'ip-address'
    Start-Process -FilePath $env:ComSpec -ArgumentList $temp
  }
}; $Reboot = @()
#End of reboot section
##################################


##################################
#Swap HA
#$SetConfig = $Devices | Out-GridView -OutputMode Multiple
$Priority = "90"
$Config = "<preemptive>yes</preemptive><device-priority>$Priority</device-priority>"
$XPath = '/config/devices/entry/deviceconfig/high-availability/group/election-option'
for ($ix = 0; $ix -lt $SetConfig.Count; $ix++) {
  $Serial = $SetConfig[$ix].serial
  $Result = Set-PANConfig -Data $Config -Target $Serial -XPath $XPath
  if ($Result.status -eq 'success') {
    $Result = Invoke-PANCommit -Target $Serial
    if ($Result.status -eq 'success') {
      write-host ("Updated "+$SetConfig[$ix].hostname)
    } else {
      write-host ("Unable to commit "+$SetConfig[$ix].hostname)
      $Result.OuterXml
    }
  } else {
    write-host ("Unable to update "+$SetConfig[$ix].hostname)
    $result.msg
  }
}

#Show HA status
for ($ix = 0; $ix -lt $SetConfig.count; $ix++) {
  $HA = Invoke-PANOperation -SkipCertificateCheck -Command ("<show><high-availability><state/></high-availability></show>&target="+$SetConfig[$ix].serial)
  $SetConfig[$ix].hostname+" "+$HA.result.group.'local-info'.state
}
#End of swap HA
##################################


##################################
#Install
#$Install_Devices = $Active | Out-GridView -OutputMode Multiple
#$Install_Devices = $passive | Out-GridView -OutputMode Multiple
for ($ix = 0; $ix -lt $Install_Devices.count; $ix++) {
  $Install = Invoke-PANOperation -Command ("<request><system><software><install><version>$Version</version></install></software></system></request>&target="+$Install_Devices[$ix].serial)
  if ($Install.status -eq 'success') {
    Add-Member -Force -InputObject $Install_Devices[$ix] -NotePropertyMembers @{
      'install-job-id'=$Install.result.job
    }
    write-host ("Started Install on "+$Install_Devices[$ix].hostname)
  } else {
    write-host ("Unable to Install "+$Install_Devices[$ix].hostname)
    $Install.OuterXML
  }
};

#Check Status of install job
$Check_Devices = $Install_Devices | Out-GridView -OutputMode Multiple
for ($ix = 0; $ix -lt $Check_Devices.count; $ix++) {
  if ($Check_Devices[$ix].'install-job-id') {
    $Result = Invoke-PANOperation -Command ("<show><jobs><id>"+$Check_Devices[$ix].'install-job-id'+"</id></jobs></show>&target="+$Check_Devices[$ix].serial)
    write-host ("Install stauts on "+$Check_Devices[$ix].hostname+" is: "+$Result.result.job.status+" "+$Result.result.job.details.line)
  } else {
    write-host ("No Install Job on "+$Check_Devices[$ix].hostname)
  }
}
#End install Section
##################################
