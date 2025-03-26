$credential = Get-Credential
$tsig = 'xxxx'

$BasicAuth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($credential.UserName+':'+$credential.GetNetworkCredential().password))
$Headers = @{
    'Content-Type'='application/x-www-form-urlencoded'
    'Authorization'='Basic '+$BasicAuth
}
$Response = Invoke-RestMethod -Method "Post" -Headers $Headers -Body "grant_type=client_credentials&scope=tsg_id:$tsig" -Uri 'https://auth.apps.paloaltonetworks.com/oauth2/access_token'

$Auth = $Response.access_token
$Headers = @{
    'Authorization' ="Bearer $auth"
    'Content-Type'='application/json'
}

$XPath = '/config/devices/entry/device-group/entry[@name="CUSTOMER_NAME"]/address'
#$XPath = '/config/shared/address'
$Addresses = (Get-PANConfig -Show -XPath $XPath -tag 'SavantLab').result.address.entry | Out-GridView -OutputMode Multiple
#Put Addresses
$HashArguments = @{
  URI = "https://api.strata.paloaltonetworks.com"+"/config/objects/v1/addresses"+"?folder=All"
  Headers = $Headers
  Method = 'Post'
}
foreach ($Address in $Addresses) {
  if ($Address.fqdn) {
    $data = '{"name":"'+$address.name+'","fqdn":"'+$address.'fqdn'+'"}'
  } elseif ($Address.'ip-netmask') {
    $data = '{"name":"'+$address.name+'","ip_netmask":"'+$address.'ip-netmask'+'"}'
  } elseif ($Address.'ip-range') {
    $data = '{"name":"'+$address.name+'","ip_range":"'+$address.'ip-range'+'"}'
  } else {
    $data = ''
    "don't know"
  }
  #$data
  $Response = Invoke-RestMethod @HashArguments -Body $data
  $Response
}

#List addresses
#$HashArguments = @{
#  URI = "https://api.strata.paloaltonetworks.com"+"/config/objects/v1/addresses"+"?folder=All"
#  Headers = $Headers
#  Method = 'Get'
#}
#$Addresses = Invoke-RestMethod @HashArguments

$XPath = '/config/devices/entry/device-group/entry[@name="CUSTOMER_NAME"]/service'
#$XPath = '/config/shared/service'
$Services = (Get-PANConfig -Show -XPath $XPath -tag 'SavantLab').result.service.entry | Out-GridView -OutputMode Multiple
#Put Services
$HashArguments = @{
  URI = "https://api.strata.paloaltonetworks.com"+"/config/objects/v1/services"+"?folder=All"
  Headers = $Headers
  Method = 'Post'
}
foreach ($Service in $Services) {
  if ($service.protocol.tcp) {
    $data = '{"name":"'+$service.name+'","protocol":{"tcp":{"port":"'+$service.protocol.tcp.port+'"}}}'
  } elseif ($service.protocol.udp) {
    $data = '{"name":"'+$service.name+'","protocol":{"udp":{"port":"'+$service.protocol.udp.port+'"}}}'
  } else {
    $data = ''
    "don't know"
  }
  #$data
  $Response = Invoke-RestMethod @HashArguments -Body $data
  $Response
}

#Put Service Groups
#$HashArguments = @{
#  URI = "https://api.strata.paloaltonetworks.com"+"/config/objects/v1/service-groups"+"?folder=All"
#  Headers = $Headers
#  Method = 'Post'
#}
#foreach ($ServiceGroup in $ServiceGroups) {
#  $data = '{"name": "'+$ServiceGroup.name+'","members": ["'+$ServiceGroup.members.member[0]+'"'
#  for ($ix = 1; $ix -lt $ServiceGroup.members.member.count; $ix++) {
#    $data+=',"'+$ServiceGroup.members.member[$ix]+'"'
#  }
#  $data+=']}'
#  $Response = Invoke-RestMethod @HashArguments -Body $data
#  $Response
#}

$XPath = '/config/devices/entry/device-group/entry[@name="CUSTOMER_NAME"]/address-group'
#$XPath = '/config/shared/address-group'
#Put Address Groups
$AddressGroups = (Get-PANConfig -Show -XPath $XPath -tag 'SavantLab').result.'address-group'.entry | Out-GridView -OutputMode Multiple
$HashArguments = @{
  URI = "https://api.strata.paloaltonetworks.com"+"/config/objects/v1/address-groups"+"?folder=All"
  Headers = $Headers
  Method = 'Post'
}
foreach ($AddressGroup in $AddressGroups) {
  $data = '{"name": "'+$AddressGroup.name+'","static": ["'+$AddressGroup.static.member[0]+'"'
  for ($ix = 1; $ix -lt $AddressGroup.static.member.count; $ix++) {
    $data+=',"'+$AddressGroup.static.member[$ix]+'"'
  }
  $data+=']}'
  #$data
  $Response = Invoke-RestMethod @HashArguments -Body $data
  $Response
}

#Get Rules
#$HashArguments = @{
#  URI = "https://api.strata.paloaltonetworks.com"+"/config/security/v1/security-rules"+"?folder=AO"
#  Headers = $Headers
#  Method = 'Get'
#}
#$ExistingRules = Invoke-RestMethod @HashArguments


$ImportThese = @{
    Import1 = @{ source = "/config/shared/pre-rulebase/security/rules"; destination = "ngfw-shared" }
    Import2 = @{ source = '/config/devices/entry/device-group/entry[@name="CUST_DG1"]/post-rulebase/security/rules'; destination = "SCM-Folder1" }
    Import3 = @{ source = '/config/devices/entry/device-group/entry[@name="CUST_DG2"]/post-rulebase/security/rules'; destination = "SCM-Folder2" }
}
foreach ($Import in $ImportThese.GetEnumerator()) {
  $source = $Import.Value.source
  $destination = $Import.Value.destination
  $Rules = (Get-PANConfig -Show -XPath $source -tag 'SavantLab').result.rules.entry
  $HashArguments = @{
    URI = "https://api.strata.paloaltonetworks.com"+"/config/security/v1/security-rules"+"?folder="+$destination
    Headers = $Headers
    Method = 'Post'
  }
  foreach ($Rule in $Rules) {
    $description = $Rule.description
    if (-not $description) {
      $description = "Imported from WG"
    }
    $data = '{
      "name": "'+$Rule.name+'",
      "description": "'+$description+'",
      "tag": ["'+$Rule.'profile-setting'.group.member+'"],
      "from": ["'+($Rule.from.member -join '","')+'"],"to":["'+($Rule.to.member -join '","')+'"],"application":["'+($Rule.application.member -join '","')+'"],"category":["any"],
      "source": ["'+($Rule.source.member -join '","')+'"],"source_user":["any"],
      "destination": ["'+($Rule.destination.member -join '","')+'"],"destination_user":["any"],
      "negate_destination": '+(""+($Rule.'negate-destination' -eq "yes")).ToLower()+',
      "service": ["'+($Rule.service.member -join '","')+'"],
      "profile_setting": {"group":[ "'+$Rule.'profile-setting'.group.member+'"]},
      "log_setting": "Cortex Data Lake","log_end": true,"action":"allow"
    }'
    #$data
    $Response = Invoke-RestMethod @HashArguments -Body $data
    $Response
  }
}
