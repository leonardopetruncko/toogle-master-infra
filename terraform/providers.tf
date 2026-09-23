terraform {
  required_version = ">= 1.10.0" # use_lockfile (lock nativo do S3) exige 1.10+

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
  }

  # ---------------------------------------------------------------------
  # Backend remoto (requisito da Fase 3): o estado nunca fica local.
  # O bucket precisa ser criado uma única vez, fora deste projeto (ver
  # bootstrap/), porque o backend não pode depender de um recurso que ele
  # mesmo gerencia. O lock usa o arquivo nativo do S3 (use_lockfile), que é
  # criado automaticamente dentro do próprio bucket.
  # Troque os valores abaixo ou rode:
  #   terraform init -backend-config=backend.hcl
  # ---------------------------------------------------------------------
  backend "s3" {
    bucket       = "toogle-master-tfstate-431204285928" # Troque pelo nome do seu bucket (precisa ser único globalmente).
    key          = "fase3/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # Lock nativo do S3 (Terraform >= 1.10); dispensa o DynamoDB.
  }
}

provider "aws" {
  region = var.region
}

# ---------------------------------------------------------------------------
# Os providers kubernetes e helm apontam para o cluster EKS recém-criado e usam
# o AWS CLI (exec plugin) para gerar o token de autenticação. Assim, nenhuma
# credencial estática de kubeconfig vai parar no state.
# ---------------------------------------------------------------------------
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
