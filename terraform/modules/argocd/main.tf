# Instala o Argo CD no cluster EKS usando o Helm chart oficial.
# Só roda depois que o cluster e o node group já existem (ver providers.tf e o
# comentário do módulo argocd no main.tf da raiz).

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # GitOps pull-based: o Argo CD roda dentro do cluster e acompanha o
  # repositório GitOps por conta própria. Nenhuma credencial ou kubeconfig
  # precisa sair do cluster.
  set {
    name  = "configs.params.server\\.insecure"
    value = "true" # Simplifica o acesso via port-forward/ALB sem configurar TLS extra no desafio.
  }

  dynamic "set" {
    for_each = var.argocd_admin_password_bcrypt != "" ? [1] : []
    content {
      name  = "configs.secret.argocdServerAdminPassword"
      value = var.argocd_admin_password_bcrypt
    }
  }
}

output "namespace" {
  value = kubernetes_namespace.argocd.metadata[0].name
}
