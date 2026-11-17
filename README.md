# ToggleMaster: infraestrutura (IaC) e operação

Repositório de **infraestrutura como código** do ToggleMaster (Tech Challenge FIAP).
O deploy das aplicações é feito por GitOps, em repositório separado:
https://github.com/leonardopetruncko/toogle-master-gitops

![Arquitetura da Fase 4](https://raw.githubusercontent.com/leonardopetruncko/toogle-master-gitops/main/docs/arquitetura/arquitetura-fase4.png)

## Estrutura

```
terraform/            # VPC, EKS, RDS x3, ElastiCache, DynamoDB, SQS, ECR e ArgoCD
├── bootstrap/        # bucket S3 do backend remoto (roda 1x por conta)
└── modules/          # network, eks, database, messaging, ecr, argocd
scripts/              # operação da Fase 4 (PowerShell)
├── fase4-secrets.ps1       # bancos + secrets do cluster (roda a cada sessão)
├── testar-integracoes.ps1  # valida Datadog, PagerDuty e Discord sem subir o cluster
├── gerar-trafego.ps1       # tráfego contínuo nos 5 microsserviços
├── simular-falha.ps1       # injeta a falha silenciosa (demo de self-healing)
└── sql/                    # criação dos bancos, schema e dados de demonstração
COMO-SUBIR-FASE4.md   # passo a passo para subir e destruir o ambiente
```

## Por onde começar

1. `COMO-SUBIR-FASE4.md`, parte A: contas (Datadog, PagerDuty, Discord) e `fase4.env`.
2. Parte B: subir a infraestrutura e o cluster a cada sessão do AWS Academy.
3. As melhorias e correções desta fase estão em
   [toogle-master-gitops/docs/melhorias-fase4.md](https://github.com/leonardopetruncko/toogle-master-gitops/blob/main/docs/melhorias-fase4.md).

> Segredos nunca entram neste repositório: `scripts/fase4.env` e `terraform/terraform.tfvars`
> estão no `.gitignore`.
