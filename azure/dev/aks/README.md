# Composición AKS (Azure, dev)

Equivalente Azure de `aws/dev/eks/` con el mismo contrato module-v2: el workspace de
cada equipo (`workspaces/<team>/terraform/azure/dev/aks-NN/main.tf`) declara el provider
`azurerm`, una `variable "azure_subscription_id"` inyectada por el Terraform Agent y este
módulo referenciado por tag. Rutas relativas a la raíz del repositorio.

| Archivo / módulo | Rol |
|---|---|
| `../aks.yaml` | Catálogo (schema v2): versiones, región, rango de servicios, tamaños, límites y `max_pods` |
| `../network.yaml` | Pool de red propio de Azure (Regla A, `10.0.0.0/16`–`10.99.0.0/16`) |
| `naming/azure.json`, `modules/naming` | Nombres deterministas (`akseusd005dev01`, `rgeus…`, `steus…`, `vnet…`) |
| `modules/azure/networking` | VNet, subredes system/user, NSG, NAT gateway |
| `modules/azure/identity` | Identidades administradas del plano de control y kubelet |
| `modules/azure/aks` | Clúster privado, sin cuentas locales, Entra ID + Azure RBAC, Azure CNI clásico, pool system |
| `modules/azure/nodepools` | Pool user |
| `modules/azure/access` | Lectura acotada (p. ej. SRE Agent), sin Secrets |

Modos: `DESIGN_WITHOUT_AZURE_SUBSCRIPTION` (por defecto, no crea nada), `NETWORKING_ONLY`
y `AKS_CLUSTER`. Compuertas en plan: red aprobada (`NETWORKING_PENDING`), al menos un
grupo admin de Platform Engineering (`ACCESS_PENDING`), capacidad de las subredes para
el CNI clásico (`SUBNET_CAPACITY_EXCEEDED`: `(max_count + 1) × (max_pods + 1)` debe caber
en la subred de cada pool) y credenciales de la suscripción revisada del equipo
(`SUBSCRIPTION_MISMATCH`).

El resource group del workspace (`names.rg`) y su backend de State los crea el bootstrap
del backend (GP02-Azure, fase F4); este módulo nunca los crea. Generar o validar
estos archivos no autoriza ejecución ni aprovisionamiento.
