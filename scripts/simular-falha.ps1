<#
.SYNOPSIS
  Fase 4 ("A Prova Real"): injeta uma falha silenciosa no auth-service.

.DESCRIPTION
  Chama POST /admin/chaos (protegido pela MASTER_KEY). A partir daí o pod do auth-service
  responde 500 no /validate, mas o /health continua 200: o Kubernetes NÃO percebe sozinho.
  Quem percebe é a observabilidade:
    taxa de 5xx > 5% por 1 min -> alerta FIRING no Grafana -> incidente no PagerDuty
    -> mensagem no Discord -> self-healer faz rollout restart -> pod novo, sem a falha.
  A MASTER_KEY vem direto do Secret (secretKeyRef): não passa pelo terminal.

.EXAMPLE
  .\simular-falha.ps1              # liga a falha
  .\simular-falha.ps1 -Desligar    # desliga manualmente (sem esperar o self-healing)
#>
param([switch]$Desligar)

$ErrorActionPreference = "Continue"
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$ns = "toogle-master"
$metodo = if ($Desligar) { "DELETE" } else { "POST" }

kubectl get secret auth-service-secret -n $ns 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "ERRO: rode o fase4-secrets.ps1 antes." -ForegroundColor Red; exit 1 }

kubectl delete pod chaos -n $ns --ignore-not-found --wait=true 2>$null | Out-Null
$manifest = @"
apiVersion: v1
kind: Pod
metadata:
  name: chaos
  namespace: toogle-master
spec:
  restartPolicy: Never
  containers:
    - name: curl
      image: curlimages/curl:8.11.1
      env:
        - name: MASTER_KEY
          valueFrom:
            secretKeyRef:
              name: auth-service-secret
              key: MASTER_KEY
      command: ["sh", "-c"]
      args:
        - 'curl -s -X $metodo -H "Authorization: Bearer `$MASTER_KEY" http://auth-service:8001/admin/chaos'
"@

$manifest | kubectl apply -f - | Out-Null
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/chaos -n $ns --timeout=90s | Out-Null
$resp = kubectl logs chaos -n $ns
kubectl delete pod chaos -n $ns --ignore-not-found 2>$null | Out-Null
Write-Host "Resposta do auth-service: $resp"

if ($Desligar) {
    Write-Host "Falha desligada." -ForegroundColor Yellow
    exit 0
}

Write-Host "`nFALHA INJETADA no auth-service." -ForegroundColor Red
Write-Host "O que acompanhar (cada um num terminal / aba):"
Write-Host "  1. Grafana (dashboard + Alerting > Alert rules): taxa de 5xx subindo; FIRING em ~1-2 min"
Write-Host "  2. PagerDuty: incidente aberto | Discord: mensagem do alerta"
Write-Host "  3. kubectl logs -f deploy/self-healer -n observability      # o runbook sendo executado"
Write-Host "  4. kubectl get pods -n toogle-master -l app=auth-service -w  # o pod sendo trocado"
