variable "region" {
  description = "Região da AWS."
  type        = string
  default     = "us-east-1"
}

variable "db_password" {
  description = "Senha do usuário master dos bancos."
  type        = string
  sensitive   = true
}

variable "lab_role_name" {
  description = "Nome da IAM Role já existente a ser reutilizada (AWS Academy/Lab). No Academy não criamos Roles/Policies via Terraform."
  type        = string
  default     = "LabRole"
}

variable "project_name" {
  description = "Nome do projeto, usado nas tags."
  type        = string
  default     = "ToogleMaster"
}

variable "install_argocd" {
  description = "Se true, instala o Argo CD via Helm neste apply. Exige que o cluster já exista, então normalmente é usado no 2º apply."
  type        = bool
  default     = false
}
