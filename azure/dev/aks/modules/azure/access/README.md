# access (Azure)

Read-only Azure RBAC on the cluster for approved principals by purpose (for example
the SRE Agent): "Azure Kubernetes Service Cluster User Role" and "Azure Kubernetes
Service RBAC Reader", which excludes Secrets. Admin access is not granted here: it
comes only from the Entra ID admin groups (Platform Engineering) set on the cluster.
Developers receive no direct access.

Private API without a jump host: the cluster API has no public endpoint and there is no
VM in the VNet. Platform Engineering admin groups and the agents reach it with
`az aks command invoke`, through the Azure API, using a narrow custom role of this
cluster (`<aks>-command-invoke`: read the cluster, run a command, read its result).
Kubernetes authorization is still each caller's own Azure RBAC role.

Agent identities (`agents`), one Entra ID principal per team and purpose, issued by the
platform (Azure has no session tags, so team isolation is the principal itself):

- `bot`: "Azure Kubernetes Service RBAC Reader" (read-only, no Secrets).
- `tools`: "Azure Kubernetes Service RBAC Cluster Admin" (Argo CD bootstrap).
- `cleanup`: custom role `<aks>-destroy-cleanup` with data actions only: scale Argo CD's
  application controller and delete LoadBalancer Services and Ingresses (Destroy pre-step).

Custom roles are scoped to the workspace resource group (their only assignable scope), so
the identity that applies this module needs to create role definitions there.
