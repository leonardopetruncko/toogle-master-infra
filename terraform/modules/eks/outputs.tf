output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  value = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# SG que o EKS cria e anexa aos nós do node group gerenciado (diferente da SG que
# passamos em vpc_config, essa vai para as ENIs do control plane). É a origem real
# do tráfego dos pods, então é ela que precisa de acesso ao RDS e ao ElastiCache.
output "cluster_security_group_id" {
  value = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
