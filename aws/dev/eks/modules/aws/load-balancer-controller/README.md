# load-balancer-controller

AWS side of the AWS Load Balancer Controller: the EKS Pod Identity agent (managed add-on, default version for the
cluster's Kubernetes version) and the Pod Identity association of `aws-load-balancer-controller/aws-load-balancer-controller` (own namespace: the Argo CD project of the tools never deploys to `kube-system`) with the
role `<names.eks>-lb-controller` created by `modules/aws/iam` (upstream controller IAM policy, workload boundary).

The controller itself is a platform tool (Helm chart) installed by Argo CD from `platform-engineering-tools`. It
creates the internal NLB of the Istio gateway in the node subnets (`kubernetes.io/role/internal-elb=1`) with the
`<names.sg>-ingress` security group passed by annotation; leftovers after a failed Destroy are removed by the
Terraform Agent (TD-063).

The Pod Identity agent is created here, not through `reviewed_execution.addons`, so the EKS-bootstrapped vpc-cni,
kube-proxy and CoreDNS stay as they are. Do not list `eks-pod-identity-agent` in `reviewed_execution.addons`.

Terraform >=1.9,<2; provider AWS pinned to 6.20.0.
