# Roles GitHub OIDC reutilizables — implementación local

Este módulo define roles independientes para Plan, Apply y Destroy. Validate no
utiliza AWS. No se ha autorizado desplegar recursos o activar GitHub Actions.
No configura provider/backend y no crea, consulta ni modifica proveedores OIDC.
La raíz consumidora deberá configurar el proveedor AWS para la cuenta autorizada.

## Interfaz obligatoria

| Variable | Contenido |
|---|---|
| `oidc_provider_arn` | ARN exacto del proveedor GitHub existente en la cuenta de los roles |
| `executor_repository` | OWNER/REPOSITORY ejecutor, independiente del repositorio de módulos |
| `executor_repository_id` | ID inmutable verificado del repositorio ejecutor |
| `executor_owner_id` | ID inmutable verificado de su propietario |
| `roles` | Mapa con exactamente plan/apply/destroy; cada entrada contiene name, subject, ref y environment |
| `state_scope` | bucket_name, team_id, environment e instance de un único estado autorizado |

`roles` exige nombres distintos (también sin distinguir mayúsculas/minúsculas),
environments distintos y referencias exactas de rama. No inventa nombres ni
identidades. Los subjects deben ser los verificados del environment indicado,
con formato clásico `repo:OWNER/REPO:environment:ENVIRONMENT` o con IDs inmutables
`repo:OWNER@OWNER_ID/REPO@REPO_ID:environment:ENVIRONMENT`. No hay defaults de cuenta,
ARN, repositorio, IDs, nombres, environments, subjects o alcance del estado.

Cada rol puede recibir `job_workflow_ref` opcional, exclusivamente para restringir
un workflow reutilizable cuyo claim se haya verificado. No suministrarlo para jobs
que no lo emitan. No hay condiciones libres que permitan reemplazar aud/sub o
introducir operadores más permisivos. Los subjects personalizados y workflows
sin environments quedan fuera de esta interfaz: requieren una revisión específica.

## Confianza y permisos

Se reutiliza `trust.json.template` sin modificarlo. La confianza generada conserva
sts:AssumeRoleWithWebIdentity y aud=sts.amazonaws.com. Solo utiliza StringEquals,
con proveedor exacto, sujeto, repositorio, IDs, ref y environment; opcionalmente
job_workflow_ref. No hay StringLike, comodines amplios ni alternativas OR entre
ramas/environments. El ARN existente no demuestra por sí solo propiedad o
existencia del proveedor: el propietario debe comprobarlas antes de desplegar.

Se reutiliza `state.json` sin modificarlo. Las referencias concretas
de bucket/key se sustituyen por el alcance autorizado para derivar:
`states/<team_id>/aws/<environment>/<instance>/terraform.tfstate`.
Los segmentos no admiten rutas, traversal o comodines. La partición del ARN S3 se
obtiene del ARN del proveedor OIDC, sin consultar AWS.

`backend_access_phases` es un set optativo de plan/apply/destroy, vacío por defecto.
Sin opt-in solo se definen tres roles sin políticas de permisos adjuntas. Por cada
fase habilitada se define una política inline de backend, con las mismas acciones:
ListBucket condicionado a las keys exactas del estado/lock; GetObject/PutObject del
estado; GetObject/PutObject/DeleteObject solo del lock. No hay acceso global al
bucket ni DeleteObject del estado. El rol Plan con backend no es puramente de solo
lectura: se conserva la política existente, incluyendo estado/locking.

**Aprovisionamiento bloqueado:** no hay políticas de aprovisionamiento aprobadas.
El módulo no acepta JSON arbitrario de permisos ni adjunta políticas administrativas,
managed policies o permisos EKS/EC2/IAM/KMS. No define access keys ni AssumeRole hacia
otros roles. Backend y aprovisionamiento están separados; cualquier interfaz futura
para estos últimos requiere revisión de acciones/recursos/condiciones por fase.
La ausencia de grants en el módulo no certifica ausencia de permisos externos por
resource policies, attachments añadidos fuera de Terraform o configuración de cuenta.

## Recursos y outputs

- `aws_iam_role.phase`: exactamente tres instancias, claves plan/apply/destroy.
- `aws_iam_role_policy.backend`: cero a tres instancias, según opt-in por fase.
- Ningún proveedor OIDC, usuario, access key o recurso EKS/S3 adicional.

Outputs: `role_arns`, `role_names`, `trust_policies`, `backend_policy`, `state_key`
y `provisioning_enabled` (siempre false para esta implementación).
No se creó raíz bootstrap ni configuración de despliegue con valores reales.

## Validación operativa

Desde la raíz del repositorio, ejecutar el validador operativo documentado en
README.md: `tools/terraform/validate-offline.py`. Requiere Terraform compatible,
mirror local y lockfile existente revisado con AWS 6.20.0. Usa copias temporales,
backend=false y lockfile=readonly, sin AWS ni descargas. Pruebas adicionales deben
permanecer fuera del repositorio publicable. No cambiar versiones o lockfiles
para resolver un fallo de validación.

## Decisiones antes de usarlo

El propietario debe confirmar cuenta/partición y proveedor existente, repositorio
ejecutor e IDs, subjects reales, ramas/environments y nombres aprobados de roles.
Los environments deben tener protecciones verificadas y el proveedor AWS de la
raíz debe restringir la cuenta correcta. Confirmar ausencia de colisiones con roles
existentes o acordar adopción separada; no hay importaciones/migraciones implícitas.

Elegir expresamente qué fases reciben backend. Para habilitar aprovisionamiento,
se necesita un inventario y políticas aprobadas por fase: ninguna política, o una
política acotada revisada posteriormente; no se ofrece una alternativa administrativa.
Si se exige permissions boundary, su ARN y aplicación requieren aprobación antes
de desplegar; este módulo todavía no la configura.

GitHub Actions permanece inactivo. El rol Destroy de este módulo no autoriza borrar
el bucket de backend. El bootstrap administrativo de IAM debe ser independiente
de los roles que administra, sin depender de ellos para su primera ejecución.

Referencias oficiales:
- [Condiciones OIDC de IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_iam-condition-keys.html).
