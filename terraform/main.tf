data "aws_iam_role" "lab_role" {
  name = var.lab_role_name
}

module "network" {
  source       = "./modules/network"
  project_name = var.project_name
}

module "eks" {
  source = "./modules/eks"

  project_name            = var.project_name
  lab_role_arn            = data.aws_iam_role.lab_role.arn
  public_subnet_ids       = module.network.public_subnet_ids
  private_subnet_ids      = module.network.private_subnet_ids
  nodes_security_group_id = module.network.nodes_security_group_id
}

module "database" {
  source = "./modules/database"

  project_name                  = var.project_name
  db_subnet_group_name          = module.network.db_subnet_group_name
  elasticache_subnet_group_name = module.network.elasticache_subnet_group_name
  data_security_group_id        = module.network.data_security_group_id
  db_password                   = var.db_password
}

module "messaging" {
  source       = "./modules/messaging"
  project_name = var.project_name
}

module "ecr" {
  source       = "./modules/ecr"
  project_name = var.project_name
}

# O módulo do Argo CD depende de o cluster EKS já existir e estar acessível.
# Recomendação: rode o primeiro "terraform apply" com install_argocd=false para
# subir VPC, EKS e bancos; depois rode "terraform apply -var install_argocd=true".
# Isso evita o problema clássico dos providers kubernetes/helm tentarem se
# autenticar num cluster que ainda não existe no mesmo plan.
module "argocd" {
  source = "./modules/argocd"
  count  = var.install_argocd ? 1 : 0

  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# Acesso dos pods aos dados.
# Os nós do node group gerenciado recebem a SG criada pelo EKS (eks-cluster-sg-*),
# e não a "nodes" deste projeto. Como os pods usam o ENI do nó (VPC CNI), é essa SG
# que precisa ser liberada no RDS e no ElastiCache.
# ---------------------------------------------------------------------------
resource "aws_security_group_rule" "data_postgres_from_eks_nodes" {
  type                     = "ingress"
  description              = "PostgreSQL a partir dos nos do EKS (SG gerenciada pelo EKS)"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.network.data_security_group_id
  source_security_group_id = module.eks.cluster_security_group_id
}

resource "aws_security_group_rule" "data_redis_from_eks_nodes" {
  type                     = "ingress"
  description              = "Redis a partir dos nos do EKS (SG gerenciada pelo EKS)"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = module.network.data_security_group_id
  source_security_group_id = module.eks.cluster_security_group_id
}
