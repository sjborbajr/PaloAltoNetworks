Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module pan-power

#Gather Data
$Devices = (Invoke-PANOperation -SkipCertificateCheck -Command "<show><devices><connected></connected></devices></show>").result.devices.entry
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


#Check for software and download
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  $Result = Invoke-PANOperation -Command ("<request><system><software><check/></software></system></request>&target="+$Devices[$ix].serial)
  if ($Result.status -eq 'success') {
    if (($Result.result.'sw-updates'.versions.entry | ? {$_.version -eq $Version}).downloaded -ne "yes") {
      $Download = Invoke-PANOperation -Command ("<request><system><software><download><version>$Version</version></download></software></system></request>&target="+$Devices[$ix].serial)
      if ($Download.status -eq 'success') {
        Add-Member -InputObject $Devices[$ix] -NotePropertyMembers @{
          'download-job-id'=$Download.result.job
        }
        write-host ("Started download on "+$Devices[$ix].hostname)
      } else {
        write-host ("Unable to download "+$Devices[$ix].hostname)
        $Download
      }
    } else {
      write-host ("Install already downloaded on "+$Devices[$ix].hostname)
    }
  } else {
    write-host ("Unable check for software "+$Devices[$ix].hostname)
    $Result
  }
}

#Check Status of download job
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  if ($Devices[$ix].'download-job-id') {
    $Result = Invoke-PANOperation -Command ("<show><jobs><id>"+$Devices[$ix].'download-job-id'+"</id></jobs></show>&target="+$Devices[$ix].serial)
    write-host ("Download stauts on "+$Devices[$ix].hostname+" is:")
    $Result.result.job.status
    $Result.result.job.details.line
  } else {
    write-host ("No Download Job on "+$Devices[$ix].hostname)
  }
}


#Install
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  $Install = Invoke-PANOperation -Command ("<request><system><software><install><version>$Version</version></install></software></system></request>&target="+$Devices[$ix].serial)
  if ($Install.status -eq 'success') {
    Add-Member -InputObject $Devices[$ix] -NotePropertyMembers @{
      'install-job-id'=$Install.result.job
    }
    write-host ("Started Install on "+$Devices[$ix].hostname)
  } else {
    write-host ("Unable to Install "+$Devices[$ix].hostname)
    $Install
  }
}

#Check Status of install job
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  if ($Devices[$ix].'install-job-id') {
    $Result = Invoke-PANOperation -Command ("<show><jobs><id>"+$Devices[$ix].'install-job-id'+"</id></jobs></show>&target="+$Devices[$ix].serial)
    write-host ("Install stauts on "+$Devices[$ix].hostname+" is:")
    $Result.result.job.status
    $Result.result.job.details.line
  } else {
    write-host ("No Install Job on "+$Devices[$ix].hostname)
  }
}


#Reboot devices (comment out command as safety)
for ($ix = 0; $ix -lt $Reboot.count; $ix++) {
  #$Result = Invoke-PANOperation -Command "<request><restart><system/></restart></request>" -Target $Reboot[$ix].serial
  Add-Member -InputObject $Reboot[$ix] -NotePropertyMembers @{
    'reboot'=$result
  }
  $temp = "/c ping -t  "+$Reboot[$ix].'ip-address'
  Start-Process -FilePath $env:ComSpec -ArgumentList $temp
}

