#Requires -Version 7
param([switch]$Update)
$ErrorActionPreference = 'Stop'
$ConfigPath = Join-Path $PSScriptRoot 'acme-config.xml'
$LogPath    = Join-Path $PSScriptRoot 'acme.log'

function Write-Log {
  param([string]$Message, [ValidateSet('INFO', 'ERROR')][string]$Level = 'INFO')
  $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
  Add-Content -Path $LogPath -Value $line
  Write-Host $line
}

function Read-Value {
  param([string]$Prompt, [string]$Default)
  $suffix = if ($Default) { " [$Default]" } else { '' }
  $v = Read-Host "$Prompt$suffix"
  if ([string]::IsNullOrWhiteSpace($v)) { $Default } else { $v.Trim() }
}

function Read-Choice {
  param([string]$Prompt, [string[]]$Choices, [string]$Default)
  do { $v = Read-Value "$Prompt ($($Choices -join ', '))" $Default } while ($v -notin $Choices)
  $v
}

function Read-Secret {
  param([string]$Prompt, [securestring]$Default)
  $hint = if ($Default) { ' [Enter = keep existing]' } else { ' [Enter = skip]' }
  $v = Read-Host "$Prompt$hint" -AsSecureString
  if ($v.Length -eq 0) { $Default } else { $v }
}

function ConvertFrom-Secure {
  param([securestring]$Secure)
  [System.Net.NetworkCredential]::new('', $Secure).Password
}

function Check-Response {
  param($Response, [string]$Step)
  $x = if ($Response -is [xml]) { $Response } else { [xml]($Response -join '') }
  if ($x.response.status -ne 'success') { throw "$Step failed: $($x.OuterXml)" }
}

function Wait-PanJob {
  param(
    [Parameter(Mandatory)] [string]$JobId,
    [Parameter(Mandatory)] [string]$PanIp,
    [Parameter(Mandatory)] [string]$ApiKey,
    [int]$PollSeconds = 5
  )

  do {
    Start-Sleep -Seconds $PollSeconds
    $statusUri = "https://$PanIp/api/?type=op&cmd=<show><jobs><id>$JobId</id></jobs></show>&key=$ApiKey"
    $statusResp = Invoke-RestMethod -Uri $statusUri -Method Get -SkipCertificateCheck
    $status = $statusResp.response.result.job.status
    Write-Log "  Job $JobId status: $status"
  } while ($status.Length -gt 1 -and $status -ne 'FIN')

  $result = $statusResp.response.result.job.result
  if ($result -ne 'OK') { throw "Job $JobId finished with result: $result" }
  Write-Log "  Job $JobId completed OK"
}

if ($Update -or -not (Test-Path $ConfigPath)) {
  $old = if (Test-Path $ConfigPath) { Import-Clixml $ConfigPath } else { @{} }

  $Mode = Read-Choice 'Mode' @('Panorama', 'Firewall') $(if ($old.Mode) { $old.Mode } else { 'Panorama' })
  $AcmeServer = Read-Value 'ACME server (LE_STAGE, LE_PROD, or directory URL)' $(if ($old.AcmeServer) { $old.AcmeServer } else { 'LE_STAGE' })
  $LE = $AcmeServer -like 'LE_*'

  $Validation = Read-Choice 'Validation method' @('none', 'cloudflare', 'azure-direct', 'azure-alias', 'aws-direct', 'aws-alias') $old.Validation

  $cfg = @{
    Mode       = $Mode
    AcmeServer = $AcmeServer
    EabKeyId   = if (-not $LE) { Read-Value  'EAB key ID'   $old.EabKeyId }
    EabHmacKey = if (-not $LE) { Read-Secret 'EAB HMAC key' $old.EabHmacKey }
    Validation = $Validation
    Contact    = Read-Value 'Contact email' $old.Contact
    Domains    = @()
  }

  switch -Wildcard ($Validation) {
    'cloudflare' {
      $cfg.CFToken = Read-Secret 'Cloudflare API token' $old.CFToken
    }
    'azure-*' {
      $cfg.AZSubscriptionId  = Read-Value  'Azure subscription ID'    $old.AZSubscriptionId
      $cfg.AZTenantId        = Read-Value  'Azure tenant ID'          $old.AZTenantId
      $cfg.AZAppClientId     = Read-Value  'Azure app client ID'      $old.AZAppClientId
      $cfg.AZAppClientSecret = Read-Secret 'Azure app client secret'  $old.AZAppClientSecret
    }
    'aws-*' {
      $cfg.R53AccessKey = Read-Value  'AWS access key ID'     $old.R53AccessKey
      $cfg.R53SecretKey = Read-Secret 'AWS secret access key' $old.R53SecretKey
    }
  }

  $cfg.PANMGMTIP = Read-Value "$Mode mgmt IP" $old.PANMGMTIP
  $PANUser = Read-Value "$Mode admin user (blank = keep existing API key)"
  $cfg.PANKey = if ($PANUser) {
    $PANPass = Read-Host "$Mode admin password" -AsSecureString
    $uri = "https://$($cfg.PANMGMTIP)/api/?type=keygen&user=$([uri]::EscapeDataString($PANUser))&password=$([uri]::EscapeDataString((ConvertFrom-Secure $PANPass)))"
    $r = Invoke-RestMethod -Uri $uri -SkipCertificateCheck
    ConvertTo-SecureString $r.response.result.key -AsPlainText -Force
  } else { $old.PANKey }

  Write-Host "`nDomains (- or blank name to finish)"
  $i = 0
  while ($true) {
    $o = if ($i -lt $old.Domains.Count) { $old.Domains[$i] } else { @{} }
    $name = Read-Value "Certificate FQDN #$($i+1)" $o.Name
    if (-not $name -or $name -eq "-") { break }
    $dom = @{ Name = $name }
    if ($Validation -like '*-alias') {
      $dom.DnsAlias = Read-Value '  CNAME target' $o.DnsAlias
    }
    if ($Mode -eq 'Panorama') {
      $dom.Template  = Read-Value '  Panorama template'      $o.Template
      $dom.PushStack = Read-Value '  Template stack to push' $o.PushStack
    }
    $cfg.Domains += $dom
    $i++
  }

  $cfg | Export-Clixml -Path $ConfigPath
  Write-Log "Configuration saved to $ConfigPath"
  if ($Update) { return }
}

function main {
  Write-Log 'Run started'
  $cfg        = Import-Clixml $ConfigPath
  $Mode       = $cfg.Mode
  $AcmeServer = $cfg.AcmeServer
  $EabKeyId   = $cfg.EabKeyId
  $EabHmacKey = if ($cfg.EabHmacKey) { ConvertFrom-Secure $cfg.EabHmacKey }
  $Contact    = $cfg.Contact
  $PANMGMTIP  = $cfg.PANMGMTIP
  $PANKey     = ConvertFrom-Secure $cfg.PANKey
  $Domains    = $cfg.Domains
  $PfxPass    = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 31 | ForEach-Object { [char]$_ })

  $Plugin = $null
  $PluginArgs = $null
  switch -Wildcard ($cfg.Validation) {
    'cloudflare' {
      $Plugin = 'Cloudflare'
      $PluginArgs = @{ CFToken = $cfg.CFToken }
    }
    'azure-*' {
      $Plugin = 'Azure'
      $PluginArgs = @{
        AZSubscriptionId = $cfg.AZSubscriptionId
        AZTenantId       = $cfg.AZTenantId
        AZAppCred        = [pscredential]::new($cfg.AZAppClientId, $cfg.AZAppClientSecret)
      }
    }
    'aws-*' {
      $Plugin = 'Route53'
      $PluginArgs = @{ R53AccessKey = $cfg.R53AccessKey; R53SecretKey = $cfg.R53SecretKey }
    }
  }
  Write-Log "Config loaded: mode=$Mode, validation=$($cfg.Validation), $($Domains.Length) Certs"

  if (-not (Get-Module -ListAvailable -Name Posh-ACME)) {
    Install-Module -Name Posh-ACME -Scope CurrentUser -Force
    Write-Log 'Installed Posh-ACME'
  }
  Import-Module Posh-ACME
  Set-PAServer $AcmeServer
  Write-Log "ACME server set: $AcmeServer"

  if (-not (Get-PAAccount)) {
    $acct = @{ Contact = $Contact; AcceptTOS = $true }
    if ($EabKeyId) { $acct += @{ ExtAcctKID = $EabKeyId; ExtAcctHMACKey = $EabHmacKey } }
    New-PAAccount @acct | Out-Null
    Write-Log 'ACME account created'
  }
  if ((Get-PAAccount).status -ne 'valid') { throw "ACME account status is '$((Get-PAAccount).status)'" }
  Write-Log 'ACME account valid'

  foreach ($d in $Domains) {
    Write-Log "Requesting cert for $($d.Name)"
    $order = @{ Domain = $d.Name; PfxPass = $PfxPass; Force = $true }
    if ($Plugin)     { $order += @{ Plugin = $Plugin; PluginArgs = $PluginArgs } }
    if ($d.DnsAlias) { $order += @{ DnsAlias = $d.DnsAlias } }
    $CertOrder = New-PACertificate @order
    if (-not ($CertOrder -and (Test-Path $CertOrder.FullChainFile) -and (Test-Path $CertOrder.PfxFullChain))) { throw "Certificate files missing for $($d.Name)" }
    Write-Log "Cert for $($d.Name) issued (thumbprint $($CertOrder.Thumbprint))"

    $FullChain = $CertOrder.FullChainFile
    $PfxPath   = $CertOrder.PfxFullChain
    $tpl = if ($Mode -eq 'Panorama') { "&target-tpl=$($d.Template)" }

    Write-Log "Uploading cert for $($d.Name) to $Mode"
    $certUri = "https://$PANMGMTIP/api/?type=import&category=certificate&certificate-name=$($d.Name)&format=pem$tpl&key=$PANKey"
    $response = curl.exe -k -F "file=@$FullChain" $certUri
    Check-Response $response "Certificate import for $($d.Name)"

    $keyUri = "https://$PANMGMTIP/api/?type=import&category=private-key&certificate-name=$($d.Name)&format=pkcs12&passphrase=$PfxPass$tpl&key=$PANKey"
    $response = curl.exe -k -F "file=@$PfxPath" $keyUri
    Check-Response $response "Private key import for $($d.Name)"
    Write-Log "Upload complete for $($d.Name)"
  }

  Write-Log "Committing changes on $Mode"
  $commitUri = "https://$PANMGMTIP/api/?type=commit&cmd=<commit/>&key=$PANKey"
  $commitResp = Invoke-RestMethod -Uri $commitUri -Method Post -SkipCertificateCheck
  $commitJob = $commitResp.response.result.job
  Check-Response $commitResp "$Mode commit"

  if ($Mode -eq 'Panorama') {
    Wait-PanJob -JobId $commitJob -PanIp $PANMGMTIP -ApiKey $PANKey
    foreach ($stack in ($Domains.PushStack | Select-Object -Unique)) {
      Write-Log "Pushing to template stack $stack"
      $cmd = "<commit-all><template-stack><name>$stack</name></template-stack></commit-all>"
      $pushUri = "https://$PANMGMTIP/api/?type=commit&action=all&key=$PANKey&cmd=$([uri]::EscapeDataString($cmd))"
      $pushResp = Invoke-RestMethod -Uri $pushUri -Method Post -SkipCertificateCheck
      Write-Log "Push started for $stack - job $($pushResp.response.result.job)"
    }
  } else {
    Write-Log "Commit job $commitJob started (not waiting)"
  }
}
try { main }
catch {
  Write-Log "FAILED: $($_.Exception.Message)" 'ERROR'
  exit 1
}
Write-Log 'Run finished'
