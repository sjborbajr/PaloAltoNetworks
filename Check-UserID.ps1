Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module pan-power

#Gather Data
$Devices = (Invoke-PANOperation -Command "<show><devices><connected></connected></devices></show>").result.devices.entry
$Devices = $Devices | ? { $_.ha.state -ne 'passive'}
$GroupCount = 46
$AgentCount = 2
$MinIPCount = 500
$Max = $Devices.count
$LoopAverage = ($GroupCount + 6) + 1500

for ($ix = 0; $ix -lt $Devices.count; $ix++) {
  $ix2 = 0; $i = 0; $StartLoopTime = Get-Date
  $ParentLoopText = ("Working on "+$Devices[$ix].hostname)
  if (($ix+1 -gt 6) -or ($ix+1 -gt ($Max * 0.1))) {
    Write-Progress -id 1 -Activity "Running Loop" -Status $ParentLoopText -PercentComplete (($ix/$Max)*100) -SecondsRemaining ($LoopAverage*($Max - $ix)/1000)
  } else {
    Write-Progress -id 1 -Activity "Running Loop" -Status $ParentLoopText -PercentComplete (($ix/$Max)*100)
  }

  Write-Progress -ParentId 1 -id 2 -Activity ("Getting User to IP Mappings") -PercentComplete ((($i++)/(6+$GroupCount))*100)
  $IP_Mapping = Invoke-PANOperation -SkipCertificateCheck -Command "<show><user><ip-user-mapping><all></all></ip-user-mapping></user></show>" -Target $Devices[$ix].serial
  if ( (0 + $IP_Mapping.result.count ) -lt $MinIPCount ) {
    $Devices[$ix].hostname+"`t"+$IP_Mapping.result.count
  }

  Write-Progress -ParentId 1 -id 2 -Activity ("Getting User ID Agent Count") -PercentComplete ((($i++)/(6+$GroupCount))*100)
  $Agent = Invoke-PANOperation -SkipCertificateCheck -Command "<show><user><user-id-agent><statistics/></user-id-agent></user></show>" -Target $Devices[$ix].serial
  if ($Agent.result.entry.Connected.Count -ne $AgentCount) {
    $Devices[$ix].hostname+"`tAgents"
    $Agent.result.entry
  }

  Write-Progress -ParentId 1 -id 2 -Activity ("Getting Group List") -PercentComplete ((($i++)/(6+$GroupCount))*100)
  $Groups = Invoke-PANOperation -SkipCertificateCheck -Command "<show><user><group-mapping><state>all</state></group-mapping></user></show>" -Target $Devices[$ix].serial
  $Groups = $Groups.result.'#cdata-section'.Split("`n")
  $Group_Count = 0 + ($Groups | Select-String "Number of Groups:")[0].tostring().trim().split(":")[1].trim()
  $Groups = $Groups | Select-String "cn="
  $Groups = $Groups | % { $_[0].tostring().Trim() }
  if ($Groups.Count -ne $GroupCount) {
    $Devices[$ix].hostname+"`tGroups:"+$Groups.Count
  } else {
    for ($ix2 = 0; $ix2 -lt $Groups.Count; $ix2++) {
      Write-Progress -ParentId 1 -id 2 -Activity ("Getting Group membership of group "+($ix2+1)) -PercentComplete ((($i++)/(6+$GroupCount))*100)
      $Members = Invoke-PANOperation -SkipCertificateCheck -Command ("<show><user><group><name>"+$Groups[$ix2]+"</name></group></user></show>") -Target $Devices[$ix].serial
      if ($Members.result.'#cdata-section' -match "does not exist or does not have members") {
        $Devices[$ix].hostname+"`t"+$Members.result.'#cdata-section'.tostring().trim()
      }
    }
  }

  $LoopTime = (New-TimeSpan -Start $StartLoopTime -End (Get-Date)).TotalMilliseconds
  $Delta = $LoopTime - $LoopAverage
  if ( (100*($i/$Max)) -lt 10) { $LoopAverage = $LoopAverage + $Delta/$i } Else {
                                 $LoopAverage = $LoopAverage + $Delta/($Max*.1)
  }
}
