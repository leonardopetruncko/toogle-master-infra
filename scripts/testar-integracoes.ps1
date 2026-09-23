<#
.SYNOPSIS
  Testa as 3 integrações da Fase 4 (Datadog, PagerDuty e Discord) SEM precisar do cluster.

.DESCRIPTION
  Lê o fase4.env e valida cada chave contra a API real:
    Datadog   -> valida a API key e descobre o site da conta (US1, US3, US5, EU ou AP1).
    PagerDuty -> abre um incidente de teste e resolve na sequência.
    Discord   -> posta uma mensagem de teste no canal.
  Rode isto ANTES de subir o Lab: chave errada aqui custa 1 minuto, chave errada lá custa crédito.

.EXAMPLE
  .\testar-integracoes.ps1
#>
param([string]$EnvFile = (Join-Path $PSScriptRoot "fase4.env"))

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Ok([string]$m) { Write-Host "  [OK]    $m" -ForegroundColor Green }
function Falha([string]$m) { Write-Host "  [FALHA] $m" -ForegroundColor Red }
function Aviso([string]$m) { Write-Host "  [!]     $m" -ForegroundColor Yellow }

if (-not (Test-Path $EnvFile)) {
    Write-Host "ERRO: não achei $EnvFile. Copie fase4.env.example para fase4.env e preencha." -ForegroundColor Red
    exit 1
}
$cfg = @{}
foreach ($linha in Get-Content $EnvFile -Encoding UTF8) {
    $l = $linha.Trim()
    if ($l -eq "" -or $l.StartsWith("#") -or -not $l.Contains("=")) { continue }
    $i = $l.IndexOf("=")
    $cfg[$l.Substring(0, $i).Trim()] = $l.Substring($i + 1).Trim().Trim('"')
}
$erros = 0

# --------------------------------------------------------------- Datadog
Write-Host "`n== Datadog (API key) ==" -ForegroundColor Cyan
$dd = $cfg["DATADOG_API_KEY"]
if ([string]::IsNullOrEmpty($dd)) {
    Falha "DATADOG_API_KEY vazio no fase4.env"; $erros++
}
else {
    if ($dd.Length -ne 32) { Aviso "a API key do Datadog tem 32 caracteres; a sua tem $($dd.Length). Confira se nao copiou uma Application Key." }
    # Descobre o site da conta: a mesma key so e valida no site onde foi criada.
    $sites = @("datadoghq.com", "us3.datadoghq.com", "us5.datadoghq.com", "datadoghq.eu", "ap1.datadoghq.com")
    if (-not [string]::IsNullOrEmpty($cfg["DATADOG_SITE"])) { $sites = @($cfg["DATADOG_SITE"]) + ($sites | Where-Object { $_ -ne $cfg["DATADOG_SITE"] }) }
    $siteOk = $null
    foreach ($site in $sites) {
        try {
            $r = Invoke-RestMethod -Method Get -Uri "https://api.$site/api/v1/validate" -Headers @{ "DD-API-KEY" = $dd } -TimeoutSec 15
            if ($r.valid) { $siteOk = $site; break }
        }
        catch { }
    }
    if ($siteOk) {
        Ok "chave valida no site $siteOk"
        if ($siteOk -ne "datadoghq.com") {
            Aviso "troque 'site: datadoghq.com' por 'site: $siteOk' em toogle-master-gitops\observability\values\otel-collector.yaml"
        }
        # Envia um log de teste pelo mesmo caminho que o Collector vai usar (Datadog intake).
        $corpo = @{ ddsource = "teste-fase4"; service = "teste-fase4"; hostname = $env:COMPUTERNAME; message = "ToggleMaster Fase 4: teste de integracao" } | ConvertTo-Json
        try {
            Invoke-RestMethod -Method Post -Uri "https://http-intake.logs.$siteOk/api/v2/logs" -Headers @{ "DD-API-KEY" = $dd; "Content-Type" = "application/json" } -Body $corpo -TimeoutSec 20 | Out-Null
            Ok "log de teste enviado. Veja em Logs > Search (service:teste-fase4)."
        }
        catch { Aviso "a key e valida, mas o envio de log de teste falhou (isso nao bloqueia o APM)." }
    }
    else {
        Falha "o Datadog recusou a chave em todos os sites. Use uma API Key (Organization Settings > API Keys), nao uma Application Key."
        $erros++
    }
}

# --------------------------------------------------------------- PagerDuty
Write-Host "`n== PagerDuty (routing key da integração Events API v2) ==" -ForegroundColor Cyan
$pd = $cfg["PAGERDUTY_ROUTING_KEY"]
if ([string]::IsNullOrEmpty($pd)) {
    Falha "PAGERDUTY_ROUTING_KEY vazio no fase4.env"; $erros++
}
else {
    $dedup = "teste-fase4-toggle-master"
    $abrir = @{
        routing_key  = $pd; event_action = "trigger"; dedup_key = $dedup
        payload      = @{ summary = "[TESTE] ToggleMaster Fase 4 - validacao da integracao"; source = "script testar-integracoes"; severity = "info" }
    } | ConvertTo-Json -Depth 5
    try {
        $r = Invoke-RestMethod -Method Post -Uri "https://events.pagerduty.com/v2/enqueue" -ContentType "application/json" -Body $abrir -TimeoutSec 20
        Ok "incidente de teste criado (status: $($r.status)). Confira em Incidents no PagerDuty."
        Start-Sleep -Seconds 3
        $fechar = @{ routing_key = $pd; event_action = "resolve"; dedup_key = $dedup } | ConvertTo-Json
        Invoke-RestMethod -Method Post -Uri "https://events.pagerduty.com/v2/enqueue" -ContentType "application/json" -Body $fechar -TimeoutSec 20 | Out-Null
        Ok "incidente de teste resolvido automaticamente (é assim que o alerta vai se comportar)."
    }
    catch {
        Falha "PagerDuty recusou a chave. Use a Integration Key de uma integração 'Events API V2' do serviço."
        $erros++
    }
}

# --------------------------------------------------------------- Discord
Write-Host "`n== Discord (webhook do canal) ==" -ForegroundColor Cyan
$dc = $cfg["DISCORD_WEBHOOK_URL"]
if ([string]::IsNullOrEmpty($dc)) {
    Falha "DISCORD_WEBHOOK_URL vazio no fase4.env"; $erros++
}
elseif ($dc -notmatch "^https://(discord|discordapp)\.com/api/webhooks/") {
    Falha "a URL não parece um webhook do Discord (tem que começar com https://discord.com/api/webhooks/)"; $erros++
}
else {
    $msg = @{ username = "self-healer"; content = "**[TESTE]** Integracao da Fase 4 configurada. E aqui que vao cair os alertas do ToggleMaster." } | ConvertTo-Json
    try {
        Invoke-RestMethod -Method Post -Uri $dc -ContentType "application/json" -Body $msg -TimeoutSec 20 | Out-Null
        Ok "mensagem de teste enviada. Confira o canal."
    }
    catch {
        Falha "o Discord recusou o webhook (URL errada ou webhook apagado)."
        $erros++
    }
}

Write-Host ""
if ($erros -eq 0) {
    Write-Host "TUDO CERTO: as 3 integrações responderam. Pode subir o Lab." -ForegroundColor Green
}
else {
    Write-Host "$erros integração(ões) com problema. Corrija o fase4.env e rode de novo." -ForegroundColor Red
    exit 1
}
