# COMO SUBIR E GRAVAR: ToggleMaster Fase 4 (conta 431204285928)

Mesmo roteiro das fases anteriores, com as novidades da Fase 4 marcadas com 🆕.

---

## PARTE A: uma vez só (antes da primeira sessão)

### A1. 🆕 Contas (≈15 min, tudo free)

| Conta | O que pegar | Onde colar |
|---|---|---|
| **Datadog** (datadoghq.com, trial free) | Organization Settings → **API Keys** → *New Key* | `DATADOG_API_KEY` |
| **PagerDuty** (free) | Services → *New Service* "ToggleMaster" → Integrations → **Events API V2** → *Integration Key* | `PAGERDUTY_ROUTING_KEY` |
| **Discord** | Canal `#incidentes` → Editar canal → Integrações → Webhooks → *Copiar URL* | `DISCORD_WEBHOOK_URL` |

```powershell
cd C:\Users\LeonardoPetrunckodos\Downloads\PROJETO-PRONTO\PROJETO-PRONTO\fiap_toogle_master_v2\scripts
copy fase4.env.example fase4.env
notepad fase4.env        # cola as 3 chaves (o fase4.env está no .gitignore)
```

> Conta do Datadog fora do site US1 (datadoghq.com)? Troque `site:` em
> `toogle-master-gitops\observability\values\otel-collector.yaml`.
> O script abaixo descobre o seu site e avisa.

```powershell
.\testar-integracoes.ps1   # valida as 3 integrações antes de gastar crédito do Lab
```

### A2. 🆕 Subir o código novo para o GitHub

Os 5 serviços (instrumentação OTel), o repo GitOps (stack de observabilidade) e o repo
principal (Terraform + scripts):

```powershell
cd C:\Users\LeonardoPetrunckodos\Downloads\PROJETO-PRONTO\PROJETO-PRONTO
$svcs="auth-service","flag-service","targeting-service","evaluation-service","analytics-service"
foreach($s in $svcs){
  git -C "_work\$s" add -A
  git -C "_work\$s" commit -m "feat(fase4): instrumentação OpenTelemetry (traces, métricas e logs correlacionados)"
  git -C "_work\$s" push
}
git -C toogle-master-gitops add -A
git -C toogle-master-gitops commit -m "feat(fase4): stack de observabilidade (Prometheus, Loki, Grafana, OTel Collector) + alertas + self-healer"
git -C toogle-master-gitops push
```

Repo principal: copie `fiap_toogle_master_v2\terraform\` (nós t3.large) e a pasta nova
`fiap_toogle_master_v2\scripts\` para ele, junto com o `.gitignore` (que protege o `fase4.env`).

> O push nos serviços dispara o CI. Com o Lab desligado, o job de push no ECR falha (normal),
> mas o lint e o DevSecOps já validam o código. As imagens são geradas na sessão (passo 5).

---

## PARTE B: a cada sessão do AWS Academy

### 1) Credenciais (Lab: AWS Details → AWS CLI: Show) + entra na pasta

```powershell
$env:AWS_ACCESS_KEY_ID="ASIA..."
$env:AWS_SECRET_ACCESS_KEY="..."
$env:AWS_SESSION_TOKEN="..."
$env:AWS_DEFAULT_REGION="us-east-1"
cd C:\Users\LeonardoPetrunckodos\Downloads\PROJETO-PRONTO\PROJETO-PRONTO\fiap_toogle_master_v2\terraform
aws sts get-caller-identity --query Account --output text      # tem que dar 431204285928
```

### 1.5) 🆕 A conta do Lab mudou? (confira SEMPRE)

O AWS Academy troca a conta entre sessões. Se o número do passo 1 for diferente do que está
no projeto, troque em todos os arquivos (bucket do state e URLs do ECR) e suba o GitOps:

```powershell
cd C:\Users\LeonardoPetrunckodos\Downloads\PROJETO-PRONTO\PROJETO-PRONTO
$antiga="431204285928"; $nova="<numero da conta nova>"
Get-ChildItem -Recurse -File -Include *.tf,*.yaml,*.md,*.sh |
  Where-Object { $_.FullName -notmatch '\\\.terraform\\|_testgitops' } |
  ForEach-Object {
    $t = Get-Content $_.FullName -Raw
    if ($t -match $antiga) { ($t -replace $antiga, $nova) | Set-Content $_.FullName -NoNewline -Encoding utf8 }
  }
git -C toogle-master-gitops add -A
git -C toogle-master-gitops commit -m "chore: aponta o ECR para a conta nova"
git -C toogle-master-gitops push
```

Depois crie o bucket do state na conta nova:

```powershell
cd fiap_toogle_master_v2\terraform\bootstrap
Remove-Item terraform.tfstate* -ErrorAction SilentlyContinue
terraform init
terraform apply -auto-approve -var bucket_name=toogle-master-tfstate-<conta nova>
```

> ⚠ O Academy tem uma SCP que bloqueia `s3:GetBucketObjectLockConfiguration`, então esse
> apply **cria o bucket e falha no refresh**. O bucket fica criado; é só seguir. Para
> terminar a configuração dele e apontar o backend:
>
> ```powershell
> $b = "toogle-master-tfstate-<conta nova>"
> aws s3api put-bucket-versioning --bucket $b --versioning-configuration Status=Enabled
> aws s3api put-public-access-block --bucket $b --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
> aws s3api put-bucket-encryption --bucket $b --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}'
> ```
>
> Por fim, troque o `bucket` do backend em `fiap_toogle_master_v2\terraform\providers.tf`.

### 2) Sobe a infra (~20 min por causa do EKS)

```powershell
terraform init
terraform apply -auto-approve
```
→ `Apply complete! Resources: 37 added.` (🆕 os nós agora são **t3.large**)

### 3) Instala o ArgoCD

```powershell
terraform apply -auto-approve -var install_argocd=true
```

### 4) Conecta no cluster

```powershell
aws eks update-kubeconfig --name toogle-cluster --region us-east-1
kubectl get nodes          # 2 nodes Ready
```

### 5) Secrets da AWS no GitHub + 🆕 rebuild das imagens

O `destroy` apaga o ECR, então as imagens precisam ser geradas de novo a cada sessão.

```powershell
cd ..\..
$svcs="auth-service","flag-service","targeting-service","evaluation-service","analytics-service"
foreach($s in $svcs){
  $env:AWS_ACCESS_KEY_ID     | gh secret set AWS_ACCESS_KEY_ID     -R "leonardopetruncko/$s"
  $env:AWS_SECRET_ACCESS_KEY | gh secret set AWS_SECRET_ACCESS_KEY -R "leonardopetruncko/$s"
  $env:AWS_SESSION_TOKEN     | gh secret set AWS_SESSION_TOKEN     -R "leonardopetruncko/$s"
  gh workflow run ci.yml -R "leonardopetruncko/$s" --ref main          # 🆕 rebuild + push no ECR
}
```
→ Os pipelines rodam em paralelo (~5-8 min). Siga para o passo 6 enquanto isso.
Acompanhe: `gh run list -R leonardopetruncko/evaluation-service -L 1`

### 6) 🆕 Bancos + secrets (ANTES do root-app)

```powershell
cd C:\Users\LeonardoPetrunckodos\Downloads\PROJETO-PRONTO\PROJETO-PRONTO
.\fiap_toogle_master_v2\scripts\fase4-secrets.ps1
```
Cria os 3 bancos com tabelas e dados da demo, a API key, os secrets dos 5 serviços e os
secrets do Datadog, PagerDuty, Discord e Grafana. No final mostra a **senha do Grafana**.

### 7) Sobe as Applications (ArgoCD) + pega a senha

```powershell
kubectl apply -f toogle-master-gitops\argocd\project\toogle-master-project.yaml
kubectl apply -f toogle-master-gitops\argocd\root-app.yaml
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
```
→ 🆕 **11 Applications** (base + 5 serviços + 5 da observabilidade), todas `Synced/Healthy`
em ~5 min. Conferir: `kubectl get applications -n argocd`

### 8) Abre as UIs (cada port-forward num terminal, deixa rodando)

```powershell
kubectl port-forward svc/argocd-server -n argocd 8080:443                        # https://localhost:8080
kubectl port-forward svc/kube-prometheus-stack-grafana -n observability 3000:80  # 🆕 http://localhost:3000
```
Grafana: `admin` + senha do passo 6 → Dashboards → ToggleMaster → **ToggleMaster - Saúde do Ecossistema**.

### 9) 🆕 Gera tráfego (deixa rodando durante a gravação)

```powershell
.\fiap_toogle_master_v2\scripts\gerar-trafego.ps1
```
Cada linha mostra os status: tudo `200` = saudável. Em ~2 min aparecem os dados no
dashboard e os serviços no Datadog (APM > Service Catalog).

### 10) Print de custos + DESTRUIR (mesma sessão!)

```powershell
cd fiap_toogle_master_v2\terraform
terraform destroy -auto-approve -var install_argocd=true
```

---

## PARTE C: 🆕 roteiro da gravação (até 25 min)

| # | Bloco | O que mostrar |
|---|---|---|
| 1 | **Contexto** (2 min) | Diagrama `docs/arquitetura/arquitetura-fase4.png`. A dor: falha silenciosa, 6h para saber e 4h para achar a causa. |
| 2 | **Visão geral** (3 min) | `kubectl get nodes`, `kubectl get pods -A`, ArgoCD com as 11 Applications Synced/Healthy (a stack nova veio pelo GitOps). |
| 3 | **Métricas, logs e OTel** (5 min) | Dashboard (recursos, req/s, erro, latência, logs ao vivo). Grafana → Explore → Loki: `{k8s_namespace_name="toogle-master"} \|= "ERRO"`. Mostrar `observability/values/otel-collector.yaml` e explicar os 3 pipelines. |
| 4 | **APM e tracing** (4 min) | Datadog → APM → **Service Map** com os 5 serviços. APM → Traces → abrir um trace do `GET /evaluate` (evaluation → flag/targeting → auth → Postgres, e o evento SQS → analytics → DynamoDB). |
| 5 | **A prova real** (8 min) | Ver abaixo. |
| 6 | **Decisões** (3 min) | Datadog x New Relic, PagerDuty x OpsGenie, alert fatigue, ArgoCD x self-healing. |

### A prova real (4 terminais lado a lado + navegador)

```powershell
# Terminal 1: tráfego rodando (passo 9)
# Terminal 2: pods do auth sendo trocados
kubectl get pods -n toogle-master -l app=auth-service -w
# Terminal 3: o runbook automatizado
kubectl logs -f deploy/self-healer -n observability
# Terminal 4: CAUSA O PROBLEMA
.\fiap_toogle_master_v2\scripts\simular-falha.ps1
```

1. Terminal 1: `auth/validate=500`, e `flags`/`rules` passam a dar `401`.
2. Dashboard: "Taxa de 5xx do auth-service" passa da linha de 5%.
3. Grafana → Alerting → Alert rules: **Pending** e depois **Firing** (~1-2 min).
4. **PagerDuty**: incidente aberto. **Discord**: mensagem 🚨 INCIDENTE detalhada.
5. Terminal 3: `RUNBOOK: alerta ... -> kubectl rollout restart deployment/auth-service`.
6. Terminal 2: pod novo `Running`, o antigo `Terminating`. Discord: 🔧 acionado e ✅ concluído.
7. Terminal 1 volta a `200`. Alerta **Resolved**: Discord ✅ RESOLVIDO e incidente resolvido no PagerDuty.

**Prints para o relatório** (tire durante a gravação): dashboard do Grafana, trace distribuído
no Datadog, mensagem no Discord e log do self-healer (terminal 3).

---

## Lembretes de sobrevivência ($50 / sessão de 4h)

- Tudo numa sessão só: sobe → confirma verde → grava → **destrói**.
- Token expirou? Renova os 3 secrets do GitHub, re-exporta no terminal e **roda o
  `fase4-secrets.ps1` de novo** (os pods de SQS/DynamoDB usam as credenciais da sessão).
- Alguma Application travada? `kubectl get applications -n argocd` e, na UI do ArgoCD, *Sync*.
- Pod em `ImagePullBackOff`: o CI do passo 5 ainda não terminou. Espere e rode
  `kubectl rollout restart deploy -n toogle-master`.
