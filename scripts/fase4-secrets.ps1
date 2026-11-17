<#
.SYNOPSIS
  Fase 4: prepara o cluster a cada sessão do AWS Academy (bancos + secrets).

.DESCRIPTION
  Rode DEPOIS do "aws eks update-kubeconfig" e ANTES de aplicar o root-app do ArgoCD.
  É idempotente: pode rodar de novo na mesma sessão sem quebrar nada.

  1. Cria os namespaces toogle-master e observability.
  2. Inicializa os 3 bancos no RDS (CREATE DATABASE, tabelas e dados da demo).
  3. Gera (ou reaproveita) a MASTER_KEY e a SERVICE_API_KEY e registra a chave no auth_db.
  4. Cria os Secrets dos 5 microsserviços a partir dos outputs do Terraform.
  5. Cria os Secrets da observabilidade (Datadog, PagerDuty, Discord, admin do Grafana)
     a partir do arquivo fase4.env (que NÃO vai para o Git).

.EXAMPLE
  .\fase4-secrets.ps1
#>
param(
    [string]$TerraformDir = (Join-Path $PSScriptRoot "..\terraform"),
    [string]$EnvFile = (Join-Path $PSScriptRoot "fase4.env")
)

# "Continue" de propósito: no PowerShell 5.1, stderr de comando nativo com "Stop" vira exceção.
# Os erros são checados pelo $LASTEXITCODE em cada passo.
$ErrorActionPreference = "Continue"
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Passo([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok([string]$msg) { Write-Host "    OK  $msg" -ForegroundColor Green }
function Aviso([string]$msg) { Write-Host "    !!  $msg" -ForegroundColor Yellow }
function Falhar([string]$msg) { Write-Host "`nERRO: $msg" -ForegroundColor Red; exit 1 }

function Novo-Hex([int]$bytes) {
    $b = New-Object byte[] $bytes
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    return -join ($b | ForEach-Object { $_.ToString("x2") })
}

function Sha256-Hex([string]$texto) {
    $hash = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($texto))
    return -join ($hash | ForEach-Object { $_.ToString("x2") })
}

function Aplicar-Namespace([string]$ns) {
    kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - | Out-Null
    if ($LASTEXITCODE -ne 0) { Falhar "não consegui criar o namespace $ns (o kubectl está apontando para o cluster?)" }
    Ok "namespace $ns"
}

function Ler-Secret([string]$ns, [string]$nome, [string]$chave) {
    $b64 = kubectl get secret $nome -n $ns -o "jsonpath={.data.$chave}" 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($b64)) { return $null }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
}

function Aplicar-Secret([string]$ns, [string]$nome, [hashtable]$dados) {
    $argumentos = @("create", "secret", "generic", $nome, "-n", $ns, "--dry-run=client", "-o", "yaml")
    foreach ($k in $dados.Keys) {
        if (-not [string]::IsNullOrEmpty($dados[$k])) { $argumentos += "--from-literal=$k=$($dados[$k])" }
    }
    $yaml = & kubectl @argumentos
    if ($LASTEXITCODE -ne 0) { Falhar "não consegui montar o secret $ns/$nome" }
    $yaml | kubectl apply -f - | Out-Null
    if ($LASTEXITCODE -ne 0) { Falhar "não consegui aplicar o secret $ns/$nome" }
    Ok "secret $ns/$nome"
}

function Rodar-Sql([string]$dbHost, [string]$arquivo, [string]$sqlExtra, [string]$senha) {
    $sql = (Get-Content $arquivo -Raw -Encoding UTF8) + "`n" + $sqlExtra + "`n"
    $pod = "psql-init-" + [IO.Path]::GetFileNameWithoutExtension($arquivo)
    kubectl delete pod $pod -n toogle-master --ignore-not-found 2>$null | Out-Null
    # Pod temporário dentro do cluster: o RDS é privado e só aceita conexão vinda dos nós do EKS.
    $saida = $sql | kubectl run $pod -n toogle-master --rm -i --quiet --restart=Never `
        --image=postgres:16-alpine --env="PGPASSWORD=$senha" --command -- `
        psql -h $dbHost -U dbuser -d postgres -v ON_ERROR_STOP=1 -q -f - 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host ($saida | Out-String); Falhar "falha ao inicializar o banco em $dbHost ($arquivo)" }
    Ok "banco inicializado: $([IO.Path]::GetFileName($arquivo)) -> $dbHost"
}

# ---------------------------------------------------------------------------
Passo "Checando pré-requisitos"
kubectl version --client 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Falhar "kubectl não encontrado no PATH" }
kubectl get nodes 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Falhar "sem acesso ao cluster. Rode: aws eks update-kubeconfig --name toogle-cluster --region us-east-1" }
Ok "cluster acessível ($(kubectl config current-context))"

if (-not (Test-Path $EnvFile)) {
    Falhar "não achei $EnvFile. Copie fase4.env.example para fase4.env e preencha as chaves."
}
$cfg = @{}
foreach ($linha in Get-Content $EnvFile -Encoding UTF8) {
    $l = $linha.Trim()
    if ($l -eq "" -or $l.StartsWith("#") -or -not $l.Contains("=")) { continue }
    $i = $l.IndexOf("=")
    $cfg[$l.Substring(0, $i).Trim()] = $l.Substring($i + 1).Trim().Trim('"')
}
foreach ($k in @("DATADOG_API_KEY", "PAGERDUTY_ROUTING_KEY", "DISCORD_WEBHOOK_URL")) {
    if ([string]::IsNullOrEmpty($cfg[$k])) { Aviso "$k vazio em fase4.env: essa integração não vai funcionar" } else { Ok "$k carregado" }
}

Passo "Lendo outputs do Terraform ($TerraformDir)"
$tfJson = terraform "-chdir=$TerraformDir" output -json
if ($LASTEXITCODE -ne 0) { Falhar "não consegui ler os outputs do Terraform (rodou o terraform apply?)" }
$tf = ($tfJson | Out-String) | ConvertFrom-Json
$authHost = $tf.rds_auth_endpoint.value.Split(":")[0]
$mainHost = $tf.rds_main_endpoint.value.Split(":")[0]
$targetingHost = $tf.rds_targeting_endpoint.value.Split(":")[0]
$redisHost = $tf.redis_endpoint.value
$sqsUrl = $tf.sqs_url.value
$dbPass = $tf.db_password.value
$dbPassUrl = [Uri]::EscapeDataString($dbPass)
Ok "RDS auth=$authHost"
Ok "RDS main=$mainHost"
Ok "RDS targeting=$targetingHost"
Ok "Redis=$redisHost | SQS=$sqsUrl"

Passo "Namespaces"
Aplicar-Namespace "toogle-master"
Aplicar-Namespace "observability"

Passo "Chaves da aplicação (reaproveita as da sessão se já existirem)"
$masterKey = Ler-Secret "toogle-master" "auth-service-secret" "MASTER_KEY"
if (-not $masterKey) { $masterKey = "mk_" + (Novo-Hex 24); Ok "MASTER_KEY nova gerada" } else { Ok "MASTER_KEY reaproveitada" }
$serviceKey = Ler-Secret "toogle-master" "evaluation-service-secret" "SERVICE_API_KEY"
if (-not $serviceKey) { $serviceKey = "tm_key_" + (Novo-Hex 32); Ok "SERVICE_API_KEY nova gerada" } else { Ok "SERVICE_API_KEY reaproveitada" }
$serviceKeyHash = Sha256-Hex $serviceKey

Passo "Inicializando os bancos (pods psql temporários dentro do cluster)"
$sqlDir = Join-Path $PSScriptRoot "sql"
Rodar-Sql $authHost (Join-Path $sqlDir "auth.sql") "INSERT INTO api_keys (name, key_hash) VALUES ('evaluation-service', '$serviceKeyHash') ON CONFLICT (key_hash) DO NOTHING;" $dbPass
Rodar-Sql $mainHost (Join-Path $sqlDir "flag.sql") "" $dbPass
Rodar-Sql $targetingHost (Join-Path $sqlDir "targeting.sql") "" $dbPass

Passo "Secrets dos microsserviços (namespace toogle-master)"
$aws = @{
    AWS_ACCESS_KEY_ID     = $env:AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY = $env:AWS_SECRET_ACCESS_KEY
    AWS_SESSION_TOKEN     = $env:AWS_SESSION_TOKEN
}
if (-not $env:AWS_ACCESS_KEY_ID) { Aviso "credenciais AWS não estão no ambiente: SQS/DynamoDB vão depender da role do nó" }

Aplicar-Secret "toogle-master" "auth-service-secret" @{
    DATABASE_URL = "postgres://dbuser:$dbPassUrl@${authHost}:5432/auth_db"
    MASTER_KEY   = $masterKey
}
Aplicar-Secret "toogle-master" "flag-service-secret" @{ DATABASE_URL = "postgres://dbuser:$dbPassUrl@${mainHost}:5432/flag_db" }
Aplicar-Secret "toogle-master" "targeting-service-secret" @{ DATABASE_URL = "postgres://dbuser:$dbPassUrl@${targetingHost}:5432/targeting_db" }
Aplicar-Secret "toogle-master" "evaluation-service-secret" (@{
        REDIS_URL       = "redis://${redisHost}:6379"
        AWS_SQS_URL     = $sqsUrl
        SERVICE_API_KEY = $serviceKey
    } + $aws)
Aplicar-Secret "toogle-master" "analytics-service-secret" (@{ AWS_SQS_URL = $sqsUrl } + $aws)

Passo "Secrets da observabilidade (namespace observability)"
$grafanaPass = $cfg["GRAFANA_ADMIN_PASSWORD"]
if ([string]::IsNullOrEmpty($grafanaPass)) {
    $grafanaPass = Ler-Secret "observability" "grafana-admin" "admin-password"
    if (-not $grafanaPass) { $grafanaPass = Novo-Hex 8 }
}
Aplicar-Secret "observability" "grafana-admin" @{ "admin-user" = "admin"; "admin-password" = $grafanaPass }
Aplicar-Secret "observability" "grafana-alerting" @{
    PAGERDUTY_ROUTING_KEY = $cfg["PAGERDUTY_ROUTING_KEY"]
    DISCORD_WEBHOOK_URL   = $cfg["DISCORD_WEBHOOK_URL"]
}
Aplicar-Secret "observability" "datadog-api" @{ "api-key" = $cfg["DATADOG_API_KEY"] }

Passo "Reiniciando o que já estiver rodando (para ler os secrets novos)"
foreach ($ns in @("toogle-master", "observability")) {
    $deps = kubectl get deployments -n $ns -o name 2>$null
    if ($deps) {
        kubectl rollout restart deployment -n $ns | Out-Null
        Ok "rollout restart em $ns"
    }
}
# O chart nomeia o DaemonSet como "otel-collector-agent": busca pelo label para não depender do nome.
$ds = kubectl get daemonset -n observability -l app.kubernetes.io/name=opentelemetry-collector -o name 2>$null
if ($ds) { kubectl rollout restart $ds -n observability | Out-Null; Ok "rollout restart no otel-collector" }

Write-Host "`n==================== PRONTO ====================" -ForegroundColor Green
Write-Host "Grafana: usuário admin | senha $grafanaPass"
Write-Host "Próximo passo (se ainda não fez):"
Write-Host "  kubectl apply -f toogle-master-gitops\argocd\project\toogle-master-project.yaml"
Write-Host "  kubectl apply -f toogle-master-gitops\argocd\root-app.yaml"
# Sai com 0 de forma explícita: o último kubectl (consulta que pode não achar nada) não
# deve fazer o script parecer que falhou.
exit 0
