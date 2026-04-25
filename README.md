# EKS on Private VPC — Terraform

Provisions an Amazon EKS cluster whose worker nodes live entirely in private
subnets, with a single NAT Gateway for controlled egress and optional VPC
Endpoints to remove internet dependency for internal AWS traffic.

## Architecture

- VPC 10.0.0.0/16 across 2 Availability Zones
- 2 Public subnets (10.0.1.0/24, 10.0.2.0/24) — Internet Gateway, NAT Gateway
- 2 Private subnets (10.0.11.0/24, 10.0.12.0/24) — EKS nodes, control-plane ENIs
- 1 NAT Gateway in the first public subnet; private subnets route 0.0.0.0/0 through it
- EKS managed node group (2 × t3.medium), private subnets only, no public IPs
- VPC Endpoints for S3 (Gateway), ECR API, ECR DKR, SSM (Interface)
- Subnets tagged for Kubernetes LB auto-discovery (kubernetes.io/role/elb, kubernetes.io/role/internal-elb, kubernetes.io/cluster/name)

## Prerequisites

- Terraform installed. Tested on v1.14.9
- AWS CLI v2 configured (aws configure) with an IAM principal that can create VPC, EKS, EC2, IAM resources
- kubectl installed
- An AWS region of your choice (defaults to eu-central-1)

Estimated cost while running: roughly $4–6 per day. (EKS control plane $0.10/h, 2× t3.medium, 1 NAT GW, interface endpoints).


attach these 3 inline IAM policy to your deployment IAM user

name: TerraformEKS-EC2


### TerraformEKS-EC2
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EC2All",
            "Effect": "Allow",
            "Action": [
                "ec2:*Vpc*",
                "ec2:*Subnet*",
                "ec2:*Gateway*",
                "ec2:*Route*",
                "ec2:*Address*",
                "ec2:*NetworkAcl*",
                "ec2:*NetworkInterface*",
                "ec2:*SecurityGroup*",
                "ec2:*Dhcp*",
                "ec2:*Tags*",
                "ec2:*Instances",
                "ec2:*LaunchTemplate*",
                "ec2:ModifyInstanceAttribute",
                "ec2:GetLaunchTemplateData",
                "ec2:AllocateAddress",
                "ec2:ReleaseAddress",
                "ec2:ModifyVpcAttribute",
                "ec2:ModifySubnetAttribute",
                "ec2:Describe*"
            ],
            "Resource": "*"
        }
    ]
}
```

### TerraformEKS-EKSAndIAM
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EKSAndIAM",
            "Effect": "Allow",
            "Action": [
                "eks:*",
                "iam:*Role*",
                "iam:*Policy*",
                "iam:*OpenIDConnectProvider*",
                "iam:*InstanceProfile*"
            ],
            "Resource": "*"
        }
    ]
}
```

### TerraformEKS-Supporting
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Supporting",
            "Effect": "Allow",
            "Action": [
                "kms:*",
                "logs:*",
                "autoscaling:*",
                "sts:GetCallerIdentity",
                "sts:AssumeRole"
            ],
            "Resource": "*"
        }
    ]
}
```
## Deploy

git clone <this-repo>
cd terraform-eks-private
cp terraform.tfvars.example terraform.tfvars   # edit if you want different values
sed -i 's/default     = true/default     = false/' variables.tf # <-- By default deployment creates VPC endpoints for internal AWS traffic. This command removes it. 

terraform init
terraform plan
terraform apply 

## Validation

Expected result after deployment

Apply complete! Resources: 64 added, 0 changed, 0 destroyed.

Outputs:

cluster_endpoint = "https://1AA4ECE0A0548BBEB27580947E183692.gr7.eu-central-1.eks.amazonaws.com"
cluster_name = "fadata-demo-eks"
cluster_region = "eu-central-1"
configure_kubectl = "aws eks update-kubeconfig --region eu-central-1 --name fadata-demo-eks"
private_subnet_ids = [
  "subnet-0d30fc0eb0a9c0a4e",
  "subnet-00c1525ffe915a7d0",
]
public_subnet_ids = [
  "subnet-0dab033c6ab3c705d",
  "subnet-0b02fe3099372691a",
]
vpc_id = "vpc-06b4081cd630ffc6b"

-----------------------------------------

aws eks update-kubeconfig --region eu-central-1 --name fadata-demo-eks ## <-- configure kubectl

Updated context arn:aws:eks:eu-central-1:999999999999:cluster/fadata-demo-eks in /home/user/.kube/your-k8s-config


----------------------------------------

kubectl get nodes # <-- check that nodes are in private subnets

NAME                                          STATUS   ROLES    AGE     VERSION
ip-10-0-11-91.eu-central-1.compute.internal   Ready    <none>   5m17s   v1.30.14-eks-bbe087e
ip-10-0-12-75.eu-central-1.compute.internal   Ready    <none>   5m17s   v1.30.14-eks-bbe087e

----------------------------------------

kubectl apply -f k8s-manifests/nginx.yaml # <-- deploy Nginx to test deployment

deployment.apps/nginx created
service/nginx created

---------------------------------------
kubectl get pods -o wide # <-- Pods run on private nodes

NAME                     READY   STATUS    RESTARTS   AGE   IP            NODE                                          NOMINATED NODE   READINESS GATES
nginx-788b78898d-4kxr9   1/1     Running   0          25s   10.0.11.225   ip-10-0-11-91.eu-central-1.compute.internal   <none>           <none>
nginx-788b78898d-xplqq   1/1     Running   0          25s   10.0.12.51    ip-10-0-12-75.eu-central-1.compute.internal   <none>           <none>

---------------------------------------

kubectl get svc nginx # <-- check if service load balancer is internal. 

NAME    TYPE           CLUSTER-IP      EXTERNAL-IP                                                                        PORT(S)        AGE
nginx   LoadBalancer   172.20.85.225   aff9646bd0ae8438f94fe8d5afd755c8-a7b18f7b59fc3e84.elb.eu-central-1.amazonaws.com   80:32748/TCP   3m18s

--------------------------------------

dig +short aff9646bd0ae8438f94fe8d5afd755c8-a7b18f7b59fc3e84.elb.eu-central-1.amazonaws.com # <-- Checking DNS of EXTERNAL-IP. Expecting private IPs
10.0.12.142
10.0.11.148

## Destroy

kubectl delete -f k8s-manifests/nginx.yaml   # <--delete LB first (frees ENIs)
terraform destroy # <-- if hangs on deleting SG, delete leftover ENIs manualy

===========================================
Destroy complete! Resources: 64 destroyed.
===========================================

NB : Do not forget to delete deploying IAM user!



