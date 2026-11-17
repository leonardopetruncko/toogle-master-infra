# COMO SUBIR E GRAVAR: ToggleMaster Fase 4 (conta 058264068417)

Mesmo roteiro das fases anteriores, com as novidades da Fase 4 marcadas com ðŸ†•.

---

## PARTE A: uma vez sÃ³ (antes da primeira sessÃ£o)

### A1. ðŸ†• Contas (â‰ˆ15 min, tudo free)

| Conta | O que pegar | Onde colar |
|---|---|---|
| **Datadog** (datadoghq.com, trial free) | Organization Settings â†’ **API Keys** â†’ *New Key* | `DATADOG_API_KEY` |
| **PagerDuty** (free) | Services â†’ *New Service* "ToggleMaster" â†’ Integrations â†’ **Events API V2** â†’ *Integration Key* | `PAGERDUTY_ROUTING_KEY` |
| **Discord** | Canal `#incidentes` â†’ Editar canal â†’ IntegraÃ§Ãµes â†’ Webhooks â†’ *Copiar URL* | `DISCORD_WEBHOOK_URL` |

```powershell
cd C:\Users\LeonardoPetrunckodos\Downloads\PROJETO-PRONTO\PROJETO-PRONTO\fiap_toogle_master_v2\scripts
copy fase4.env.example fase4.env
notepad fase4.env        # cola as 3 chaves (o fase4.env estÃ¡ no .gitignore)
```

> Conta do Datadog fora do site US1 (datadoghq.com)? Troque `site:` em
> `toogle-master-gitops\observability\values\otel-collector.yaml`.
> O script abaixo descobre o seu site e avisa.

```powershell
.\testar-integracoes.ps1   # valida as 3 integraÃ§Ãµes antes de gastar crÃ©dito do Lab
```

### A2. ðŸ†• Subir o cÃ³digo novo para o GitHub

Os 5 serviÃ§os (instrumentaÃ§Ã£o OTel), o repo GitOps (stack de observabilidade) e o repo
principal (Terraform + scripts):

```powershell
cd C:\Users\LeonardoPetrunckodos\Downloads\PROJETO-PRONTO\PROJETO-PRONTO
$svcs="auth-service","flag-service","targeting-service","evaluation-service","analytics-service"
foreach($s in $svcs){
  git -C "_work\$s" add -A
  git -C "_work\$s" commit -m "feat(fase4): instrumentaÃ§Ã£o OpenTelemetry (traces, mÃ©tricas e logs correlacionados)"
  git -C "_work\$s" push
}
git -C toogle-master-gitops add -A
git -C toogle-master-gitops commit -m "feat(fase4): stack de observabilidade (Prometheus, Loki, Grafana, OTel Collector) + alertas + self-healer"
git -C toogle-master-gitops push
```

Repo principal: copie `fiap_toogle_master_v2\terraform\` (nÃ³s t3.large) e a pasta nova
`fiap_toogle_master_v2\scripts\` para ele, junto com o `.gitignore` (que protege o `fase4.env`).

> O push nos serviÃ§os dispara o CI. Com o Lab desligado, o job de push no ECR falha (normal),
> mas o lint e o DevSecOps jÃ¡ validam o cÃ³digo. As imagens sÃ£o geradas na sessÃ£o (passo 5).

---

## PARTE B: a cada sessÃ£o do AWS Academy

### 1) Credenciais (Lab: AWS Details â†’ AWS CLI: Show) + entra na pasta

```powershell
$env:AWS_ACCESS_KEY_ID="ASIA..."
$env:AWS_SECRET_ACCESS_KEY="..."
$env:AWS_SESSION_TOKEN="..."
$env:AWS_DEFAULT_REGION="us-east-1"
cd C:\Users\LeonardoPetrunckodos\Downloads\PROJETO-PRONTO\PROJETO-PRONTO\fiap_toogle_master_v2\terraform
aws sts get-caller-identity --query Account --output text      # tem que dar 058264068417
```

### 1.5) ðŸ†• A conta do Lab mudou? (confira SEMPRE)

O AWS Academy troca a conta entre sessÃµes. Se o nÃºmero do passo 1 for diferente do que estÃ¡
no projeto, troque em todos os arquivos (bucket do state e URLs do ECR) e suba o GitOps:

```powershell
cd C:\Users\LeonardoPetrunckodos\Downloads\PROJETO-PRONTO\PROJETO-PRONTO
$antiga="058264068417"; $nova="<numero da conta nova>"
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

> âš  O Academy tem uma SCP que bloqueia `s3:GetBucketObjectLockConfiguration`, entÃ£o esse
> apply **cria o bucket e falha no refresh**. O bucket fica criado; Ã© sÃ³ seguir. Para
> terminar a configuraÃ§Ã£o dele e apontar o backend:
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
â†’ `Apply complete! Resources: 37 added.` (ðŸ†• os nÃ³s agora sÃ£o **t3.large**)

### 3) Instala o ArgoCD

```powershell
terraform apply -auto-approve -var install_argocd=true
```

### 4) Conecta no cluster

```powershell
aws eks update-kubeconfig --name toogle-cluster --region us-east-1
kubectl get nodes          # 2 nodes Ready
```

### 5) Secrets da AWS no GitHub + ðŸ†• rebuild das imagens

O `destroy` apaga o ECR, entÃ£o as imagens precisam ser geradas de novo a cada sessÃ£o.

```powershell
cd ..\..
$svcs="auth-service","flag-service","targeting-service","evaluation-service","analytics-service"
foreach($s in $svcs){
  $env:AWS_ACCESS_KEY_ID     | gh secret set AWS_ACCESS_KEY_ID     -R "leonardopetruncko/$s"
  $env:AWS_SECRET_ACCESS_KEY | gh secret set AWS_SECRET_ACCESS_KEY -R "leonardopetruncko/$s"
  $env:AWS_SESSION_TOKEN     | gh secret set AWS_SESSION_TOKEN     -R "leonardopetruncko/$s"
  gh workflow run ci.yml -R "leonardopetruncko/$s" --ref main          # ðŸ†• rebuild + push no ECR
}
```
â†’ Os pipelines rodam em paralelo (~5-8 min). Siga para o passo 6 enquanto isso.
Acompanhe: `gh run list -R leonardopetruncko/evaluation-service -L 1`

### 6) ðŸ†• Bancos + secrets (ANTES do root-app)

```powershell
cd C:\Users\LeonardoPetrunckodos\Downloads\PROJETO-PRONTO\PROJETO-PRONTO
.\fiap_toogle_master_v2\scripts\fase4-secrets.ps1
```
Cria os 3 bancos com tabelas e dados da demo, a API key, os secrets dos 5 serviÃ§os e os
secrets do Datadog, PagerDuty, Discord e Grafana. No final mostra a **senha do Grafana**.

### 7) Sobe as Applications (ArgoCD) + pega a senha

```powershell
kubectl apply -f toogle-master-gitops\argocd\project\toogle-master-project.yaml
kubectl apply -f toogle-master-gitops\argocd\root-app.yaml
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
```
â†’ ðŸ†• **11 Applications** (base + 5 serviÃ§os + 5 da observabilidade), todas `Synced/Healthy`
em ~5 min. Conferir: `kubectl get applications -n argocd`

### 8) Abre as UIs (cada port-forward num terminal, deixa rodando)

```powershell
kubectl port-forward svc/argocd-server -n argocd 8080:443                        # https://localhost:8080
kubectl port-forward svc/kube-prometheus-stack-grafana -n observability 3000:80  # ðŸ†• http://localhost:3000
```
Grafana: `admin` + senha do passo 6 â†’ Dashboards â†’ ToggleMaster â†’ **ToggleMaster - SaÃºde do Ecossistema**.

### 9) ðŸ†• Gera trÃ¡fego (deixa rodando durante a gravaÃ§Ã£o)

```powershell
.\fiap_toogle_master_v2\scripts\gerar-trafego.ps1
```
Cada linha mostra os status: tudo `200` = saudÃ¡vel. Em ~2 min aparecem os dados no
dashboard e os serviÃ§os no Datadog (APM > Service Catalog).

### 10) Print de custos + DESTRUIR (mesma sessÃ£o!)

```powershell
cd fiap_toogle_master_v2\terraform
terraform destroy -auto-approve -var install_argocd=true
```

---

## Lembretes de sobrevivÃªncia ($50 / sessÃ£o de 4h)

- Tudo numa sessÃ£o sÃ³: sobe â†’ confirma verde â†’ grava â†’ **destrÃ³i**.
- Token expirou? Renova os 3 secrets do GitHub, re-exporta no terminal e **roda o
  `fase4-secrets.ps1` de novo** (os pods de SQS/DynamoDB usam as credenciais da sessÃ£o).
- Alguma Application travada? `kubectl get applications -n argocd` e, na UI do ArgoCD, *Sync*.
- Pod em `ImagePullBackOff`: o CI do passo 5 ainda nÃ£o terminou. Espere e rode
  `kubectl rollout restart deploy -n toogle-master`.
