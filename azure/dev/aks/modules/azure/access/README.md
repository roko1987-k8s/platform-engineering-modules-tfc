# access (Azure)

Read-only Azure RBAC on the cluster for approved principals by purpose (for example
the SRE Agent): "Azure Kubernetes Service Cluster User Role" and "Azure Kubernetes
Service RBAC Reader", which excludes Secrets. Admin access is not granted here: it
comes only from the Entra ID admin groups (Platform Engineering) set on the cluster.
Developers receive no direct access.
