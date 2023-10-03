Import-Module pan-power
$firewalls = Import-Csv -Delimiter "`t" .\these.txt

$Panorama = 'IP-OF-PANORAMA' #a 10.1 firewall will only take an IP - this could change in the future

$Local_Auth = 'LOCAL-ADMIN'
$Pano_Auth  = 'TACACS'

$KeyName = $env:COMPUTERNAME+"-"+$env:USERNAME+"-"+(Get-Date).Minute+"-key"


$Pano_Key = Invoke-PANOperation -SkipCertificateCheck -Command ("<request><authkey><add><name>"+$KeyName+"</name><count>"+$firewalls.count+"</count><lifetime>50</lifetime></add></authkey></request>") -Addresses $Panorama -Tag $Pano_Auth

if ($Pano_Key.status -eq "success") {
  for ($ix = 0; $ix -lt $firewalls.count; $ix++) {
    $ShowInfo = Invoke-PANOperation -SkipCertificateCheck -Command "<show><system><info/></system></show>" -Addresses ($firewalls[$ix].IP_Address) -Tag $Local_Auth
    if ($ShowInfo.status -eq "success"){
      Add-Member -InputObject $firewalls[$ix] -NotePropertyMembers @{
        serial=$ShowInfo.result.system.serial
      }
      $response1 = set-PANConfig -Data ("<entry name='"+$firewalls[$ix].serial+"'/>") -XPath "/config/mgt-config/devices" -Addresses $Panorama -Tag $Pano_Auth
      $response2 = Invoke-PANOperation -SkipCertificateCheck -Command ("<request><authkey><set>"+$Pano_Key.authkey+"</set></authkey></request>") -Addresses ($firewalls[$ix].IP_Address) -Tag $Local_Auth
      $response3 = set-PANConfig -Data ("<panorama-server>"+$Panorama+"</panorama-server>") -XPath "/config/devices/entry[@name='localhost.localdomain']/deviceconfig/system/panorama/local-panorama" -Addresses ($firewalls[$ix].IP_Address) -Tag $Local_Auth
      $response4 = Invoke-PANCommit -Addresses ($firewalls[$ix].IP_Address) -Tag $Local_Auth
    }
  }
}
$response = Invoke-PANCommit -Addresses $Panorama -Tag $Pano_Auth
