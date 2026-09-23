variable "namespace" {
  type    = string
  default = "argocd"
}

variable "chart_version" {
  description = "Versão do Helm chart argo-cd."
  type        = string
  default     = "7.7.11"
}

variable "argocd_admin_password_bcrypt" {
  description = "Hash bcrypt da senha do admin do Argo CD. Deixe vazio para manter o secret gerado automaticamente pelo chart."
  type        = string
  default     = ""
}
