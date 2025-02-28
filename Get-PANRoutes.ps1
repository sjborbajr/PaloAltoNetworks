#One time install of pan-power from psgallery
#Install-Module -Scope CurrentUser pan-power
Import-Module pan-power
#Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass

#$AUTH_TAG = "$env:USERDOMAIN-$env:USERNAME"
#Invoke-PANKeyGen -Addresses "panorama" -SkipCertificateCheck

#import a list of firewalls from Panorama
$firewalls = (Invoke-PANOperation -SkipCertificateCheck -Command "<show><devices><connected></connected></devices></show>").result.devices.entry
$firewalls = $firewalls | ? { $_.ha.state -ne 'passive' }


for ($ix = 0; $ix -lt $firewalls.count; $ix++) {
  Write-Progress -id 1 -PercentComplete (100*($ix/$firewalls.count)) -Activity ("Getting "+$firewalls[$ix].hostname)
  $Routes = Invoke-PANOperation -SkipCertificateCheck -Command "<show><routing><route/></routing></show>" -Target $firewalls[$ix].serial
  $Routes.result.OuterXml > ($firewalls[$ix].hostname+".xml")
}
