module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Control plane placed across private subnets; public endpoint enabled so
  # you can run kubectl from your laptop. Flip to false for full private mode.
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets  # control plane ENIs in private subnets

  # Grant the IAM user running terraform admin rights inside the cluster,
  # so kubectl works immediately after apply.
  enable_cluster_creator_admin_permissions = true

  # Core add-ons managed by EKS
  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    default = {
      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      # Nodes live ONLY in private subnets — no public IPs
      subnet_ids = module.vpc.private_subnets
    }
  }

  # Least-privilege: only allow node->control-plane on 443 and
  # control-plane->node on kubelet (10250) and ephemeral ports for exec/logs.
  # The module already creates tight SG rules; we only add extra node-to-node
  # traffic needed for CoreDNS and common CNI operations.
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }
}
