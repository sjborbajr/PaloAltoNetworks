#One time install of pan-power from psgallery
#Install-Module -Scope CurrentUser pan-power
Import-Module pan-power
#Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass

$AUTH_TAG = ""
#Invoke-PANKeyGen -Addresses "Panorama" -Tag $AUTH_TAG -SkipCertificateCheck

#import a list of firewalls from Panorama
$firewalls = (Invoke-PANOperation -SkipCertificateCheck -Command "<show><devices><connected></connected></devices></show>" -Tag $AUTH_TAG).result.devices.entry
$AllArp = for ($ix = 0; $ix -lt $firewalls.count; $ix++) {
  $Arp = Invoke-PANOperation -SkipCertificateCheck -Command "<show><arp><entry name='all'/></arp></show>" -Tag $AUTH_TAG -Target $firewalls[$ix].serial
  if ($Arp.status -eq 'success') {
    $Arp.result.entries.entry
  }
}