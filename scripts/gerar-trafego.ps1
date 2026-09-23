<#
.SYNOPSIS
  Fase 4: gera tráfego contínuo nos 5 microsserviços (alimenta dashboard, traces e alerta).

.DESCRIPTION
  Sobe um pod "trafego" (curl) dentro do cluster que chama, em loop:
    evaluation-service /evaluate  -> flag-service + targeting-service -> auth-service (trace distribuído)
    flag-service /flags           -> auth-service /validate
    targeting-service /rules/...  -> auth-service /validate
    auth-service /validate
  Cada linha do log mostra o HTTP status de cada chamada.
  A API key vem direto do Secret (secretKeyRef): não passa pelo terminal.

.EXAMPLE
  .\gerar-trafego.ps1            # inicia (e mostra o log ao vivo; Ctrl+C só para de mostrar)
  .\gerar-trafego.ps1 -Parar     # remove o pod de tráfego
#>
param([switch]$Parar)

$ErrorActionPreference = "Continue"
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$ns = "toogle-master"

kubectl delete pod trafego -n $ns --ignore-not-found --wait=true 2>$null | Out-Null
if ($Parar) { Write-Host "Tráfego parado." -ForegroundColor Yellow; exit 0 }

kubectl get secret evaluation-service-secret -n $ns 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "ERRO: rode o fase4-secrets.ps1 antes." -ForegroundColor Red; exit 1 }

# Manifest via stdin (evita o problema de aspas do PowerShell 5.1 com argumentos nativos).
$manifest = @'
apiVersion: v1
kind: Pod
metadata:
  name: trafego
  namespace: toogle-master
  labels:
    app: trafego
spec:
  restartPolicy: Never
  containers:
    - name: curl
      image: curlimages/curl:8.11.1
      env:
        - name: KEY
          valueFrom:
            secretKeyRef:
              name: evaluation-service-secret
              key: SERVICE_API_KEY
      command: ["sh", "-c"]
      args:
        - |
          i=0
          while true; do
            i=$((i+1)); u="user-$((i % 50))"
            e=$(curl -s -o /dev/null -w "%{http_code}" "http://evaluation-service:8004/evaluate?user_id=$u&flag_name=enable-new-checkout")
            f=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $KEY" http://flag-service:8002/flags)
            t=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $KEY" http://targeting-service:8003/rules/enable-new-checkout)
            a=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $KEY" http://auth-service:8001/validate)
            echo "$(date +%H:%M:%S) #$i evaluate=$e flags=$f rules=$t auth/validate=$a"
            sleep 0.3
          done
'@

$manifest | kubectl apply -f - | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "ERRO ao criar o pod de tráfego." -ForegroundColor Red; exit 1 }
kubectl wait --for=condition=Ready pod/trafego -n $ns --timeout=90s | Out-Null

Write-Host "Tráfego rodando no pod 'trafego'. Mostrando o log (Ctrl+C sai do log; o tráfego continua)." -ForegroundColor Green
Write-Host "Para parar de vez: .\gerar-trafego.ps1 -Parar`n"
kubectl logs -f trafego -n $ns
