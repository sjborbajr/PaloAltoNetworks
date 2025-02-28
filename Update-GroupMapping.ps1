#Abandoned - PAN API doesn't support debug command - might have to use expect, not API, not doing at this time

If ((Get-ExecutionPolicy) -ne 'Bypass' -and (Get-ExecutionPolicy) -ne 'Unrestricted') {Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force}
Import-Module pan-power

$Devices = (Invoke-PANOperation -Command "<show><devices><connected></connected></devices></show>" -SkipCertificateCheck).result.devices.entry
$Devices = $Devices | Out-GridView -OutputMode Multiple -Title "Where to refresh?"

$GroupName = 'SomethingThatNeedsToBeFound'

ForEach ($List in $RefreshLists) {
  $Command = '<debug><user-id><refresh><group-mapping><group-mapping-name></group-mapping-name></group-mapping></refresh></user-id></debug>'
  ForEach ($Device in $Devices) {
    $Result = Invoke-PANOperation -Command $Command -Target $Device.serial -SkipCertificateCheck
    Add-Member -InputObject $Result -NotePropertyMembers @{
      Hostname  = $Device.hostname
      Type      = $Type
      List      = $List.name
    }
    $Result
  }
}
