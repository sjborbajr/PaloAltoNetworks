Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module pan-power

#Gather Data
$Devices = (Invoke-PANOperation -SkipCertificateCheck -Command "<show><devices><connected></connected></devices></show>").result.devices.entry
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  $Result = Get-PANConfig -Target $Devices[$ix].serial -Show
  if ($Result.status -eq 'success') {
    $Result.result.config.OuterXml > ($Devices[$ix].hostname+'.xml')
  } else {
    write-host ("Unable to get config "+$Devices[$ix].hostname)
  }
}

$Result = Get-PANConfig -Show
if ($Result.status -eq 'success') {
  $Result.result.config.OuterXml > ('Panorama.xml')
} else {
  write-host ("Unable to get config Panorama")
}
AN