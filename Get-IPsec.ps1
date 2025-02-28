#One time install of pan-power from psgallery
#Install-Module -Scope CurrentUser pan-power
Import-Module pan-power
#Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass

$AUTH_TAG = "$env:USERDOMAIN-$env:USERNAME"
#Invoke-PANKeyGen -Addresses "" -Tag $AUTH_TAG -SkipCertificateCheck

#import a list of firewalls from Panorama
$firewalls = (Invoke-PANOperation -SkipCertificateCheck -Command "<show><devices><connected></connected></devices></show>").result.devices.entry
$firewalls = $firewalls | ? { $_.ha.state -ne 'passive' }

$Peers = for ($ix = 0; $ix -lt $firewalls.count; $ix++) {
  (Invoke-PANOperation -SkipCertificateCheck -Command "<show><vpn><ipsec-sa/></vpn></show>" -Target $firewalls[$ix].serial).result.entries.entry | Select Remote,Name
}