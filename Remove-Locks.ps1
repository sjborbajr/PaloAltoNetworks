#One time install of pan-power from psgallery
#Install-Module -Scope CurrentUser pan-power
Import-Module pan-power
#Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass

$AUTH_TAG = "$env:USERDOMAIN-$env:USERNAME"
#Invoke-PANKeyGen -Addresses "Panorama" -Tag $AUTH_TAG -SkipCertificateCheck

#import a list of firewalls from Panorama
$firewalls = (Invoke-PANOperation -SkipCertificateCheck -Command "<show><devices><connected></connected></devices></show>" -Tag $AUTH_TAG).result.devices.entry
for ($ix = 0; $ix -lt $firewalls.count; $ix++) {
  $ShowLocks = Invoke-PANOperation -SkipCertificateCheck -Command "<show><commit-locks><vsys>all</vsys></commit-locks></show>" -Tag $AUTH_TAG -Target $firewalls[$ix].serial
  if ($ShowLocks.result.'commit-locks') {
    foreach ($Lock in $ShowLocks.result.'commit-locks'.entry) {
      "Remove/Revert on "+$firewalls[$ix].Hostname+" for "+$Lock.name[0]
      #$Revert = Invoke-PANOperation -SkipCertificateCheck -Command "<revert><config></config></revert>" -Tag $AUTH_TAG -Target $firewalls[$ix].serial
      #$RemoveLock = Invoke-PANOperation -SkipCertificateCheck -Command ("<request><commit-lock><remove><admin>"+$Lock.name[0]+"</admin></remove></commit-lock></request>") -Tag $AUTH_TAG -Target $firewalls[$ix].serial
    }
  }
}