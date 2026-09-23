variable "project_name" {
  type = string
}

variable "cluster_name" {
  type    = string
  default = "toogle-cluster"
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "lab_role_arn" {
  description = "ARN da LabRole já existente (AWS Academy), usada tanto pelo cluster EKS quanto pelo node group."
  type        = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "nodes_security_group_id" {
  type = string
}

variable "node_instance_types" {
  # Fase 4: t3.large (2 vCPU / 8 GiB, até 35 pods por nó). Com t3.medium (4 GiB, 17 pods)
  # a stack de observabilidade (Prometheus, Loki, Grafana, OTel Collector) não cabe junto dos apps.
  description = "Tipos de instância dos nós do EKS."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
}
