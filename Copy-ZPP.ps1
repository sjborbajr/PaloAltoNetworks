Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module pan-power

$Source = 'Common'
$Profile = 'default'

$Source = "/config/devices/entry/template/entry[@name='$Source']/config/devices/entry/network/profiles/zone-protection-profile/entry[@name='$Profile']"
$ZPP = (Get-PANConfig -XPath $Source).result.entry.OuterXml
$Destinations = (Get-PANConfig -XPath "/config/devices/entry/template").result.template.entry.name | Out-GridView -Title "Select destination(s)" -OutputMode Multiple
ForEach ($Destination in $Destinations){
  $XPath = "/config/devices/entry/template/entry[@name='$Destination']/config/devices/entry/network/profiles/zone-protection-profile/entry[@name='$Profile']"
  $Test = Get-PANConfig -XPath $XPath
  If ($Test.result.count -eq 1) {
    $Test = "copy"
  } else {
    "Don't copy to $Destination"
    #ask if we should create?
  }
  If ($Test -eq 'copy') {
    #$result = Edit-PANConfig -XPath $XPath -Data $ZPP
    #"Copy to $Destination"
  }
}