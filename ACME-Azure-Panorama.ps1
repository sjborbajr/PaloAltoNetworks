#Requires -Version 7
param([switch]$Update)
$ErrorActionPreference = 'Stop'
$ConfigPath = Join-Path $PSScriptRoot 'acme-config.xml'
$LogPath  = Join-Path $PSScriptRoot 'acme.log'

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
  } while ($status -ne 'FIN')

  $result = $statusResp.response.result.job.result
  if ($result -ne 'OK') { throw "Job $JobId finished with result: $result" }
  Write-Log "  Job $JobId completed OK"
}

if ($Update -or -not (Test-Path $ConfigPath)) {
  $old = if (Test-Path $ConfigPath) { Import-Clixml $ConfigPath } else { @{} }

  $PANMGMTIP = Read-Value 'Panorama mgmt IP' $old.PANMGMTIP
  $PANUser   = Read-Value 'Panorama admin user (blank = keep existing API key)'
  $PANKey  = if ($PANUser) {
    $PANPass = Read-Host 'Panorama admin password' -AsSecureString
    $uri = "https://$PANMGMTIP/api/?type=keygen&user=$([uri]::EscapeDataString($PANUser))&password=$([uri]::EscapeDataString((ConvertFrom-Secure $PANPass)))"
    $r = Invoke-RestMethod -Uri $uri -SkipCertificateCheck
    Check-Response $r 'Panorama keygen'
    ConvertTo-SecureString $r.response.result.key -AsPlainText -Force
  } else { $old.PANKey }

  $AcmeServer = Read-Value 'ACME server (LE_STAGE, LE_PROD, or directory URL)' $(if ($old.AcmeServer) { $old.AcmeServer } else { 'LE_STAGE' })
  $LE = $AcmeServer -like 'LE_*'
  $cfg = @{
    AcmeServer    = $AcmeServer
    EabKeyId      = if (-not $LE) { Read-Value  'EAB key ID'   $old.EabKeyId }
    EabHmacKey    = if (-not $LE) { Read-Secret 'EAB HMAC key' $old.EabHmacKey }
    AZSubscriptionId  = Read-Value  'Azure subscription ID'    $old.AZSubscriptionId
    AZTenantId    = Read-Value  'Azure tenant ID'        $old.AZTenantId
    AZAppClientId   = Read-Value  'Azure app client ID'      $old.AZAppClientId
    AZAppClientSecret = Read-Secret 'Azure app client secret'    $old.AZAppClientSecret
    Contact       = Read-Value  'Contact email'        $old.Contact
    PANMGMTIP     = $PANMGMTIP
    PANKey      = $PANKey
    Domains       = @()
  }

  Write-Host "`nDomains (blank name to finish)"
  $i = 0
  while ($true) {
    $o = if ($i -lt $old.Domains.Count) { $old.Domains[$i] } else { @{} }
    $name = Read-Value "Certificate FQDN #$($i+1)" $o.Name
    if (-not $name) { break }
    $cfg.Domains += @{
      Name    = $name
      DnsAlias  = Read-Value '  Validation CNAME'     $o.DnsAlias
      Template  = Read-Value '  Panorama template'    $o.Template
      PushStack = Read-Value '  Template stack to push' $o.PushStack
    }
    $i++
  }

  $cfg | Export-Clixml -Path $ConfigPath
  Write-Log "Configuration saved to $ConfigPath"
  if ($Update) { return }
}

function main {
  Write-Log 'Run started'
  $cfg = Import-Clixml $ConfigPath
  $AZSubscriptionId  = $cfg.AZSubscriptionId
  $AZTenantId        = $cfg.AZTenantId
  $AZAppClientId     = $cfg.AZAppClientId
  $AZAppClientSecret = $cfg.AZAppClientSecret
  $AcmeServer        = $cfg.AcmeServer
  $EabKeyId          = $cfg.EabKeyId
  $EabHmacKey        = if ($cfg.EabHmacKey) { ConvertFrom-Secure $cfg.EabHmacKey }
  $Contact           = $cfg.Contact
  $PANMGMTIP         = $cfg.PANMGMTIP
  $PANKey            = ConvertFrom-Secure $cfg.PANKey
  $Domains           = $cfg.Domains
  $PfxPass           = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 31 | ForEach-Object { [char]$_ })
  $AzureArgs         = @{
                        AZSubscriptionId = $AZSubscriptionId
                        AZTenantId       = $AZTenantId
                        AZAppCred        = [pscredential]::new($AZAppClientId, $AZAppClientSecret)
                      }
  Write-Log "Config loaded, $($cfg.Domains.Length) Certs"

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
    $CertOrder = New-PACertificate -Domain $d.Name -Plugin Azure -PluginArgs $AzureArgs -DnsAlias $d.DnsAlias -PfxPass $PfxPass -Force
    Write-Log "Cert for $($d.Name) issued (thumbprint $($CertOrder.Thumbprint))"
    if (-not ($CertOrder -and (Test-Path $CertOrder.FullChainFile) -and (Test-Path $CertOrder.PfxFullChain))) { throw "Certificate files missing for $($d.Name)" }

    $FullChain = $CertOrder.FullChainFile
    $PfxPath   = $CertOrder.PfxFullChain

    Write-Log "Uploading cert for $($d.Name) to template $($d.Template)"
    $certUri = "https://$PANMGMTIP/api/?type=import&category=certificate&certificate-name=$($d.Name)&format=pem&target-tpl=$($d.Template)&key=$PANKey"
    $response = curl.exe -k -F "file=@$FullChain" $certUri
    Check-Response $response "Certificate import for $($d.Name)"

    $keyUri = "https://$PANMGMTIP/api/?type=import&category=private-key&certificate-name=$($d.Name)&format=pkcs12&passphrase=$PfxPass&target-tpl=$($d.Template)&key=$PANKey"
    $response = curl.exe -k -F "file=@$PfxPath" $keyUri
    Check-Response $response "Private key import for $($d.Name)"
    Write-Log "Upload complete for $($d.Name)"

    Write-Log 'Committing changes on Panorama'
    $commitUri = "https://$PANMGMTIP/api/?type=commit&cmd=<commit/>&key=$PANKey"
    $commitResp = Invoke-RestMethod -Uri $commitUri -Method Post -SkipCertificateCheck
    Check-Response $commitResp 'Panorama commit'
    Wait-PanJob -JobId $commitResp.response.result.job -PanIp $PANMGMTIP -ApiKey $PANKey

    Write-Log "Pushing to template stack $($d.PushStack) for $($d.Name)"
    $cmd = "<commit-all><template-stack><name>$($d.PushStack)</name></template-stack></commit-all>"
    $pushUri = "https://$PANMGMTIP/api/?type=commit&action=all&key=$PANKey&cmd=$([uri]::EscapeDataString($cmd))"
    Invoke-RestMethod -Uri $pushUri -Method Post -SkipCertificateCheck | Out-Null
  }
}
try { main }
catch {
  Write-Log "FAILED: $($_.Exception.Message)" 'ERROR'
  exit 1
}
Write-Log 'Run finished'
