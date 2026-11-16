# aks (Azure)

Private AKS cluster (no public FQDN) with local accounts disabled, Entra ID and
Azure RBAC for Kubernetes (admin only through the Platform Engineering groups),
workload identity, classic Azure CNI (pods take subnet addresses; `max_pods` from
the catalog) with the catalog service range, egress
through the workspace NAT gateway and the system pool (critical add-ons only).
An optional CanNotDelete lock is the equivalent of EKS deletion protection.
