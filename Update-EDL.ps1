If ((Get-ExecutionPolicy) -ne 'Bypass' -and (Get-ExecutionPolicy) -ne 'Unrestricted') {Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force}
Import-Module pan-power

$Devices = (Invoke-PANOperation -Command "<show><devices><connected></connected></devices></show>" -SkipCertificateCheck).result.devices.entry
$Devices = $Devices | Out-GridView -OutputMode Multiple -Title "Where to refresh?"

$DynamicLists = (Get-PANConfig -XPath '/config/shared/external-list' -SkipCertificateCheck).result.'external-list'.entry
$RefreshLists = $DynamicLists.Name | Out-GridView -OutputMode Multiple -Title "What to refresh?"

ForEach ($List in $RefreshLists) {
  $List = $DynamicLists | ? {$_.name -eq $List}
  if ($List.type.ip) {
    $Type = 'ip'
  } elseif ($List.type.url){
    $Type = 'url'
  } else {
    $Type = 'unknown'
  }
  If ($Type -ne '') {
    $Command = '<request><system><external-list><refresh><type><'+$Type+'><name>'+$List.name+'</name></'+$Type+'></type></refresh></external-list></system></request>'
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
}
