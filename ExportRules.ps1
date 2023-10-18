$XML = '.\Downloads\running-config.xml'
$RuleType = 'Security'
$AllRules = @()
$AllProperties = @('Location','Type','disabled','name','description','from','to','action','negate-source','source','negate-destination','destination','service','application','category','source-user','source-hip','option','profile-setting','group-tag','tag','log-start','log-end','log-setting','schedule','rule-type','target','uuid')

$Shared = Select-Xml -Path $XML -XPath /config/shared
  $Location = 'Shared'
  $PreRules = $Shared.Node.'pre-rulebase'.$RuleType.rules.entry
  for ($ix = 0; $ix -lt $PreRules.Count; $ix++) {
    $PreRules[$ix] = Process-Rule -Location $Location -Type 'pre' -RuleXMLobj $PreRules[$ix]
  }
  
  $PostRules = $Shared.Node.'post-rulebase'.$RuleType.rules.entry
  for ($ix = 0; $ix -lt $PostRules.Count; $ix++) {
    $PostRules[$ix] = Process-Rule -Location $Location -Type 'post' -RuleXMLobj $PostRules[$ix]
  }
$AllRules = $PreRules + $PostRules

$DeviceGroups = (Select-Xml -Path $XML -XPath '/config/devices/entry/device-group').Node.entry
  for ($i = 0; $i -lt $DeviceGroups.Count; $i++) {
    $Location = $DeviceGroups[$i].name
    $PreRules = $DeviceGroups[$i].'pre-rulebase'.$RuleType.rules.entry
    for ($ix = 0; $ix -lt $PreRules.Count; $ix++) {
      $PreRules[$ix] = Process-Rule -Location $Location -Type 'pre' -RuleXMLobj $PreRules[$ix]
    }
    
    $PostRules = $DeviceGroups[$i].'post-rulebase'.$RuleType.rules.entry
    for ($ix = 0; $ix -lt $PostRules.Count; $ix++) {
      $PostRules[$ix] = Process-Rule -Location $Location -Type 'post' -RuleXMLobj $PostRules[$ix]
    }
    $AllRules = $AllRules + $PreRules + $PostRules
  }

#Export CSV bases the column names on the first object in the array, so if it doesn't have that property, it would be ignored on all other objects
# Adding an empty value to all of the properties on the first object if they don't exist
for ($i = 0; $i -lt $AllProperties.Count; $i++) {
  if (-not $AllRules[0].($AllProperties[$i])) {
    Add-Member -InputObject $AllRules[0] -NotePropertyMembers @{
      $AllProperties[$i] = ''
    }
  }
}
($AllRules | select $AllProperties) | Export-Csv -Path 'export2.csv' -NoTypeInformation

Function Process-Rule {
<#
.SYNOPSIS
  This will Process each rule

.DESCRIPTION
  This will return an object with the rule in a format that can be exported

.PARAMETER Location
  This will ba added as a note for where the rule was

.PARAMETER Type
  This will be a note for pre or post rules

.PARAMETER RuleXMLobj
  This Contains the 

.NOTES
    Author: Steve Borba https://github.com/sjborbajr
    Last Edit: 2019-04-05


#>
  [CmdletBinding()]
  Param (
    [Parameter(Mandatory=$False)]    [string]    $Location,
    [Parameter(Mandatory=$False)]    [string]    $Type,
    [Parameter(Mandatory=$true)]     [object]    $RuleXMLobj
  )

  $FlattenProperties = @('application','category','destination','destination-hip','from','option','profile-setting','service','source','source-hip','source-user','tag','target','to')

  If ($Location.GetType().Name -eq 'String') {
    Add-Member -InputObject $RuleXMLobj -NotePropertyMembers @{
      Location = $Location
    }
  }

  If ($Type.GetType().Name -eq 'String') {
    Add-Member -InputObject $RuleXMLobj -NotePropertyMembers @{
      Type = $Type
    }
  }

  for ($i = 0; $i -lt $FlattenProperties.Count; $i++) {
    if ($RuleXMLobj.($FlattenProperties[$i])) {
      $NewValue = ''+($RuleXMLobj.($FlattenProperties[$i]).InnerText.trim().Replace("`n",",").Replace("`t","").Replace(" ","")).toString()
      $RuleXMLobj.($FlattenProperties[$i]).InnerText = $NewValue
      #Write-Host $NewValue.GetType()
      #Write-Host $NewValue
    }
  }

  $RuleXMLobj
  return

}
