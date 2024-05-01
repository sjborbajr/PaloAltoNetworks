$Devices = (Invoke-PANOperation -SkipCertificateCheck -Command "<show><devices><connected></connected></devices></show>").result.devices.entry
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  $HA = Invoke-PANOperation -SkipCertificateCheck -Command ("<show><high-availability><state/></high-availability></show>&target="+$Devices[$ix].serial)
  Add-Member -InputObject $Devices[$ix] -NotePropertyMembers @{
    'ha-running-sync'=$HA.result.group.'running-sync'
    'ha-type'=$HA.result.group.mode
    'ha-state'=$HA.result.group.'local-info'.state
    'ha1-encrypt-enable'=$HA.result.group.'local-info'.'ha1-encrypt-enable'
    'ha-priority'=$HA.result.group.'local-info'.priority
    'ha-preemptive'=$HA.result.group.'local-info'.preemptive
  }
}
$XPaths = @(
            "/config/mgt-config/password-complexity"
            "/config/shared"
            "/config/devices/entry/network/profiles"
            "/config/devices/entry/network/ike"
            "/config/devices/entry/network/qos"
            "/config/devices/entry/deviceconfig/system/update-schedule"
            "/config/devices/entry/deviceconfig/system/service"
            "/config/devices/entry/deviceconfig/system/dns-setting"
            "/config/devices/entry/vsys/entry/rulebase/security/rules"
            )
$Remove = "Yes"
$Remove = "No"
for ($ix = 0; $ix -lt $Devices.Count; $ix++) {
  $Changed = 'No'
  ForEach ($XPath in $XPaths) {
    $XPath_Split = $XPath.Split("/")
    $Test = Get-PANConfig -XPath $XPath -Show -Target $Devices[$ix].serial
    If (($Test.result.($XPath_Split[($XPath_Split.Count-1)]).InnerXml).length -gt 0) {
      If ($Changed -eq "no") {
        $Changed = "Yes"
        $Devices[$ix].hostname + " - $ix - " + $Devices[$ix].'ip-address'
      }
      If ($Remove -eq 'yes') {
        $Result = Remove-PANConfig -XPath $XPath -Target $Devices[$ix].serial
        $Result
      } else {
        $XPath+" - "+($Test.result.($XPath_Split[($XPath_Split.Count-1)]).InnerXml).length
        #$Test.result.($XPath_Split[($XPath_Split.Count-1)]).InnerXml
      }
    }
  }
  If ($Changed -eq "Yes" -and $Remove -eq "Yes") {
    $Result = Invoke-PANCommit -Target $Devices[$ix].serial
    $Result
  }
}
