output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_1a_id" {
  value = aws_subnet.public_1a.id
}

output "private_subnet_1a_id" {
  value = aws_subnet.private_1a.id
}

output "private_subnet_ids" {
  description = "All private subnet IDs (2 AZs) for EKS"
  value       = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]
}

output "db_subnet_ids" {
  description = "Subnet IDs for RDS and Redshift subnet groups (3 AZs required by Redshift Serverless)"
  value       = [aws_subnet.db_1a.id, aws_subnet.db_1b.id, aws_subnet.db_1c.id]
}

output "sg_eks_nodes_id" {
  value = aws_security_group.eks_nodes.id
}

output "sg_redshift_id" {
  value = aws_security_group.redshift.id
}
