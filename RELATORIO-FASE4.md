# Tech Challenge Fase 4: Observabilidade Total e Resposta Ativa (ToggleMaster)

## 1. Integrantes

| Nome | RM | Usuário (GitHub/Discord) |
|---|---|---|
| _preencher_ | _preencher_ | _preencher_ |

## 2. Links

- Repositório GitOps (stack de observabilidade, alertas, self-healer): https://github.com/leonardopetruncko/toogle-master-gitops
- Microsserviços instrumentados: https://github.com/leonardopetruncko/auth-service · flag-service · targeting-service · evaluation-service · analytics-service
- Workflows reutilizáveis (CI/DevSecOps): https://github.com/leonardopetruncko/reusable-workflows
- Infraestrutura (Terraform): _link do repo principal_
- Vídeo de demonstração: _link_

## 3. Arquitetura

![Arquitetura da Fase 4](toogle-master-gitops/docs/arquitetura/arquitetura-fase4.png)

A base das Fases 1 a 3 continua igual: EKS provisionado com Terraform, CI/CD com DevSecOps
no GitHub Actions e deploy pull-based pelo ArgoCD. A Fase 4 entra **por cima**, pelo mesmo
fluxo GitOps: a stack de observabilidade são Applications do ArgoCD apontando para os
Helm charts oficiais, com os values versionados no repositório.

## 4. Evidências visuais

| Evidência | Print |
|---|---|
| Dashboard customizado no Grafana | _print_ |
| Trace distribuído no Datadog (GET /evaluate) | _print_ |
| Service Map com os 5 microsserviços | _print_ |
| Notificação do incidente no Discord (ChatOps) | _print_ |
| Incidente aberto no PagerDuty | _print_ |
| Log/execução da automação de self-healing | _print_ |

## 5. Justificativa técnica

### 5.1 Arquitetura do OpenTelemetry

O **OTel Collector** é o ponto único de entrada e roteamento da telemetria. Ele roda como
**DaemonSet**, um por nó, com `internalTrafficPolicy: Local`: cada aplicação fala com o
Collector do próprio nó, o que permite ao processador `k8sattributes` identificar o pod
de origem pelo IP e anexar namespace, pod e deployment a todos os sinais.

| Sinal | Entrada | Processamento | Saída |
|---|---|---|---|
| Traces | OTLP gRPC (SDK OTel nos 5 serviços) | memory_limiter, k8sattributes, resource, batch | Datadog + connectors `datadog` (APM stats) e `spanmetrics` |
| Métricas | OTLP + spanmetrics + datadog/connector | idem | Prometheus (remote write) + Datadog |
| Logs | `filelog` (stdout de todos os pods) + OTLP | idem | Loki (OTLP nativo) + Datadog |

**Instrumentação**: em Go (auth e evaluation), SDK OTel com `otelhttp` no servidor e no
cliente HTTP, `otelsql` no PostgreSQL e spans manuais no Redis e no SQS. Em Python
(flag, targeting e analytics), SDK OTel com os instrumentors de Flask, requests, psycopg2
e botocore. O contexto do trace (W3C `traceparent`) é propagado também **pela fila SQS**,
nos MessageAttributes: o evento enviado pelo evaluation-service continua o mesmo trace
quando o analytics-service o consome, e por isso o Service Map liga os 5 serviços.
O `trace_id` também vai em cada linha de log, o que liga o log (Loki) ao trace (APM).

O connector **spanmetrics** gera métricas RED (requisições, erros e duração) a partir dos
spans, iguais para Go e Python. O painel de req/s e o alerta de 5xx usam essas métricas.

### 5.2 Datadog x New Relic

Escolhemos o **Datadog**, e a decisão tem duas partes.

**Critério técnico.** O desafio exige o OTel Collector como peça central, então o requisito
era o APM aceitar OTLP sem precisar de agente proprietário competindo com o Collector.
Datadog e New Relic atendem: o Datadog recebe OTLP pelo `datadogexporter`, e o
`datadogconnector` calcula as APM stats (as métricas que alimentam o Service Map e a
análise de latência) **dentro do próprio Collector**, sem instalar o Datadog Agent no
cluster. A instrumentação das aplicações usa exclusivamente as bibliotecas do
OpenTelemetry, então o APM é intercambiável: trocar de fornecedor é trocar um exporter
na configuração do Collector, e nenhuma linha do código das aplicações muda.

**Critério prático.** Começamos pelo New Relic, mas a conta free criada para o projeto
teve a ingestão bloqueada: todas as chaves de ingestão (License Key) foram recusadas com
HTTP 403 em todos os endpoints (Logs, Metrics, Events e OTLP), inclusive em uma conta
nova. Como o problema era da conta, e não da configuração, migramos para o Datadog.
A troca levou poucos minutos justamente por causa do desenho acima, o que na prática
comprovou o ganho de usar OpenTelemetry em vez de um agente proprietário.

Ponto de atenção do Datadog: a avaliação gratuita dura 14 dias, então a janela de
gravação precisa acontecer dentro do período.

### 5.3 PagerDuty x OpsGenie

Escolhemos o **PagerDuty**: a Atlassian encerrou a venda do OpsGenie para novos clientes
(migração para o Jira Service Management), então não era possível criar uma conta nova.
O PagerDuty tem plano gratuito, integração nativa com o Grafana Alerting (Events API v2)
e resolve o incidente automaticamente quando o alerta volta ao normal.

### 5.4 Alertas inteligentes e alert fatigue

- O alerta usa **taxa** de 5xx, não contagem: 1 erro com pouco tráfego não vira incidente.
- `for: 1m`: precisa ficar acima de 5% por 1 minuto seguido, sem disparar por pico isolado.
- Agrupamento por `alertname` + `service` e `repeat_interval` de 1h: um incidente gera
  uma notificação, e não uma por minuto.
- `noDataState: OK`: ausência de tráfego não é incidente.
- Regra, contact points e roteamento são **código** (Git), revisáveis e reproduzíveis.

### 5.5 Self-healing (Runbook Automation)

O alerta do Grafana chama, por webhook, o **self-healer**: um serviço interno em Python
(só biblioteca padrão, sem imagem própria) que executa o runbook
`kubectl rollout restart deployment/auth-service` pela API do Kubernetes.

Salvaguardas:
- **RBAC mínimo**: só `get` e `patch` em deployments do namespace `toogle-master`.
- **Allowlist** de deployments e **cooldown** de 5 min, para não ficar reiniciando em loop.
- Acompanha o rollout e reporta no Discord (acionado, concluído ou sem sucesso). Se não
  resolver, o incidente segue aberto no PagerDuty para ação humana.
- **Integração com o GitOps**: as Applications ignoram a annotation `restartedAt`. Sem
  isso, o `selfHeal` do ArgoCD desfaria o restart.

**Cenário da demo**: uma falha **silenciosa** injetada no auth-service (`/validate`
responde 500, mas o `/health` segue 200) reproduz o problema do enunciado. O Kubernetes
não percebe sozinho; a observabilidade detecta, abre o incidente, notifica e corrige
sozinha, e o restart limpa o estado corrompido do pod.

### 5.6 Limitações conhecidas (AWS Academy)

- Sem driver EBS CSI: Prometheus e Loki usam `emptyDir`, e os dados duram enquanto o
  cluster existir.
- Credenciais temporárias do Lab: os secrets são recriados a cada sessão pelo
  `fase4-secrets.ps1`.
