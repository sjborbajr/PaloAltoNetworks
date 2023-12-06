Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module pan-power

#Gather Data
$Devices = (Invoke-PANOperation -Command "<show><devices><connected></connected></devices></show>").result.devices.entry
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  #$HA = Invoke-PANOperation -SkipCertificateCheck -Command ("<show><high-availability><state/></high-availability></show>&target="+$Devices[$ix].serial)
  #Add-Member -InputObject $Devices[$ix] -NotePropertyMembers @{
  #  'ha-running-sync'=$HA.result.group.'running-sync'
  #  'ha-type'=$HA.result.group.mode
  #  'ha-state'=$HA.result.group.'local-info'.state
  #  'ha1-encrypt-enable'=$HA.result.group.'local-info'.'ha1-encrypt-enable'
  #  'ha-priority'=$HA.result.group.'local-info'.priority
  #  'ha-preemptive'=$HA.result.group.'local-info'.preemptive
  #}
}

$XPath = '/config/devices/entry/deviceconfig/system/device-telemetry'
#$Auth = (Get-PANRCTagData).Auth
#$Address = (Get-PANRCTagData).Addresses[0]
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  $Result = Get-PANConfig -XPath ($XPath+'&target='+$Devices[$ix].serial)
  if ($Result.status -eq 'success') {
    Add-Member -InputObject $Devices[$ix] -NotePropertyMembers @{
      config=$Result.result
    }
  } else {
    write-host ("Unable to get config "+$SetConfig[$ix].hostname)
  }
}

for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  $Result = Remove-PANConfig -XPath ($XPath+'&target='+$Devices[$ix].serial)
  if ($Result.status -eq 'success') {
    $Result = Invoke-RestMethod -URI ("https://"+$Address+"/api/?type=commit&cmd=<commit></commit>&"+$Auth+'&target='+$Devices[$ix].serial)
    if ($Result.response.status -eq 'success') {
      write-host ("Updated "+$Devices[$ix].hostname)
    } else {
      write-host ("Unable to commit "+$Devices[$ix].hostname)
      $Result
    }
  } else {
    write-host ("Unable to get config "+$Devices[$ix].hostname)
  }
}