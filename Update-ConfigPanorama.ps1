Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module pan-power

#Gather Data
$Devices = (Invoke-PANOperation -SkipCertificateCheck -Command "<show><devices><connected></connected></devices></show>").result.devices.entry
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  $HA = Invoke-PANOperation -SkipCertificateCheck -Command "<show><high-availability><state/></high-availability></show>" -Target $Devices[$ix].serial
  Add-Member -InputObject $Devices[$ix] -NotePropertyMembers @{
    'ha-running-sync'=$HA.result.group.'running-sync'
    'ha-type'=$HA.result.group.mode
    'ha-state'=$HA.result.group.'local-info'.state
    'ha1-encrypt-enable'=$HA.result.group.'local-info'.'ha1-encrypt-enable'
    'ha-priority'=$HA.result.group.'local-info'.priority
    'ha-preemptive'=$HA.result.group.'local-info'.preemptive
  }
}

#Select the devices to update
$SetConfig = $Devices | Out-GridView -OutputMode Multiple
#$SetConfig | Out-GridView

#Do the Update
$Config = '<preemptive>yes</preemptive><device-priority>120</device-priority>'
$XPath = '/config/devices/entry/deviceconfig/high-availability/group/election-option'
#$Auth = (Get-PANRCTagData).Auth
#$Address = (Get-PANRCTagData).Addresses[0]
for ($ix = 0; $ix -lt $SetConfig.Count; $ix++) {
  $Serial = $SetConfig[$ix].serial
  $Result = Set-PANConfig -Data $Config -Target $Serial -XPath $XPath
  if ($Result.status -eq 'success') {
    $Result = Invoke-PANCommit -Target $Serial
    if ($Result.status -eq 'success') {
      write-host ("Updated "+$SetConfig[$ix].hostname)
    } else {
      write-host ("Unable to commit "+$SetConfig[$ix].hostname)
      $Result
    }
  } else {
    write-host ("Unable to update "+$SetConfig[$ix].hostname)
    $result.msg
  }
}
