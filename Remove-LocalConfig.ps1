Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module pan-power

#Gather Data
$Devices = (Invoke-PANOperation -SkipCertificateCheck -Command "<show><devices><connected></connected></devices></show>").result.devices.entry
$Devices = $Devices | ? { $_.ha.state -ne 'passive'}
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

$XPath = '/config/devices/entry/deviceconfig/system/device-telemetry'
$XPath = '/config/mgt-config/users'
$XPath = '/config'

for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  $Result = Get-PANConfig -Target $Devices[$ix].serial
  if ($Result.status -eq 'success') {
    Add-Member -InputObject $Devices[$ix] -NotePropertyMembers @{
      config=$Result.result.config
    }
  } else {
    write-host ("Unable to get config "+$SetConfig[$ix].hostname)
  }
}

$Sync = $Devices | Out-GridView -OutputMode Multiple
#Sync HA Config
for ($ix = 0; $ix -lt $Sync.count; $ix++) {
  $Result = Invoke-PANOperation -Command "<request><high-availability><sync-to-remote><running-config></running-config></sync-to-remote></high-availability></request>" -Target $Sync[$ix].serial
}


$XPath = '/config/mgt-config/users/entry[@name="jhadmin"]'
for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  if (($Devices[$ix].config.users.entry.name -contains 'admin') -and $Devices[$ix].hostname.substring($Devices[$ix].hostname.length-2,2) -eq "01"){
    $Result = Remove-PANConfig -XPath ($XPath+'&target='+$Devices[$ix].serial)
    if ($Result.status -eq 'success') {
      $Result = Invoke-RestMethod -URI ("https://"+$Address+"/api/?type=commit&cmd=<commit></commit>&"+$Auth+'&target='+$Devices[$ix].serial)
      if ($Result.response.status -eq 'success') {
        write-host ("Updated "+$Devices[$ix].hostname)
      } else {
        write-host ("Unable to commit "+$Devices[$ix].hostname)
        $Result
      }
    } else {
      write-host ("Unable to update config "+$Devices[$ix].hostname)
    }
  }
}

#            "/config/shared"
$XPaths = @(
            "/config/mgt-config/password-complexity"
            "/config/devices/entry/network/profiles"
            "/config/devices/entry/network/ike"
            "/config/devices/entry/network/qos"
            "/config/devices/entry/deviceconfig/system/update-schedule"
            "/config/devices/entry/deviceconfig/system/service"
            "/config/devices/entry/deviceconfig/system/dns-setting"
            "/config/devices/entry/vsys/entry/rulebase"
            "/config/devices/entry/vsys/entry/service-group"
            "/config/devices/entry/vsys/entry/service"
            "/config/devices/entry/vsys/entry/address-group"
            "/config/devices/entry/vsys/entry/address"
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
  $Test = Get-PANConfig -Show -Target $Devices[$ix].serial
  $Test.result.config.OuterXml > (".\"+$Devices[$ix].hostname+".XML")
  If ($Changed -eq "Yes" -and $Remove -eq "Yes") {
    $Result = Invoke-PANCommit -Target $Devices[$ix].serial
    $Result
  }
}
