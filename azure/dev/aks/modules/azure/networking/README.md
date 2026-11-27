# networking (Azure)

VNet of one workspace with one system and one user subnet, an optional internal load
balancer subnet, an NSG per subnet and a NAT gateway with a static public IP as explicit
egress of the node subnets. CIDRs come only from the approved networking object (network
catalog, Regla A); nothing is invented here. The workspace resource group must already
exist; this module never creates it.

`rules.tf` translates `network/rules.yaml` (the rules of every cluster, defined once for
all clouds) into inbound rules on the node NSGs, with the catalog rule id as priority:
the load balancer as destination is its subnet prefix (on the User NSG), as source the
`AzureLoadBalancer` tag (health probes, plus the node port range AKS uses); there is no
jump host and no control plane object in Azure. Denials 210/212 are explicit DenyAll
rules; egress keeps Azure's defaults until rule 502.
