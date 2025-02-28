Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module pan-power

#Gather Data
$Devices = (Invoke-PANOperation -SkipCertificateCheck -Command "<show><devices><connected></connected></devices></show>").result.devices.entry


$These = $Devices | Out-GridView -OutputMode Multiple

"<show><device-telemetry><settings/></device-telemetry></show>"
"<show><device-telemetry><details/></device-telemetry></show>"
"<show><device-telemetry><stats><all/></stats></device-telemetry></show>"
"<request><certificate><fetch/></certificate></request>"
"<request><device-telemetry><collect-now/></device-telemetry></request>"


$XPath = '/config/devices/entry/deviceconfig/system/device-telemetry'
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  $config = Get-PANConfig -Target $Devices[$ix].serial -XPath $XPath
  Add-Member -InputObject $Devices[$ix] -Force -NotePropertyMembers @{
    'telemetry'=$config.result.'device-telemetry'.InnerText.Replace(" ","").Trim().Replace("`n",",")
  }
  #$Result = Remove-PANConfig -XPath $XPath -Target $Devices[$ix].serial
  #if ($Result.status -eq 'success') {
  #  Invoke-PANCommit -Target $Devices[$ix].serial
  #  if ($Result.response.status -eq 'success') {
  #    write-host ("Updated "+$Devices[$ix].hostname)
  #  } else {
  #    write-host ("Unable to commit "+$Devices[$ix].hostname)
  #    $Result
  #  }
  #} else {
  #  write-host ("Unable to update config "+$Devices[$ix].hostname)
  #}
}