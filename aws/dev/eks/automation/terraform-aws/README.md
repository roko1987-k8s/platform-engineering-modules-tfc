# Automatización Terraform AWS — preparación bloqueada

Estas plantillas NO están instaladas en `.github/workflows`. No se encontró
`platform-engineering-devs` en las ubicaciones locales revisadas.
Posteriormente se localizó el checkout central en `.`; ver `aws/dev/eks/docs/STRUCTURE.md` en ese checkout para la consolidación. No se inspeccionó
ni modificó ningún módulo EKS externo. No se consultó AWS, ni se verificó la
disponibilidad global de `s3ue1p001dev01`. No hay autorización de despliegue.

## Archivos y alcance

- `bootstrap/main.tf`: raíz independiente, estado local, bucket central P001.
- `iam/state-D001-dev-eks-01.json`: política de estado para una instancia exacta.
- `iam/trust.json.template`: confianza OIDC incompleta deliberadamente.
- `templates/backend.hcl`: configuración parcial para un root con `backend "s3" {}`.
- `templates/validate.yml.template`: fmt, init sin backend y validate; pruebas mock pendientes.
- `templates/apply.yml.template`: plan normal y apply del mismo plan en dos jobs.
- `templates/destroy.yml.template`: plan de destrucción y ejecución con aprobación separada.
- `tests/test_safety.py`: comprobaciones de regresión locales sin red ni credenciales.

El plan es el primer job de cada workflow de ejecución. No se ofrece apply de
planes arbitrarios ni de otra ejecución. No hay workflow activado en Backstage.
La ruta `workspaces/D001/terraform/aws/dev/eks-01` es una propuesta de plantilla, no un
contrato existente; adaptar al layout real mediante revisión autorizada.

## Bootstrap futuro, con autorización separada

1. Instalar Terraform >=1.10 y <2; la máquina revisada tiene 1.5.7. Revisar y fijar
   proveedor AWS 6.x mediante `.terraform.lock.hcl`, incluyendo plataformas de CI.
   Verificar compatibilidad con los módulos antes de adoptar una versión común.
2. Confirmar cuenta AWS y disponibilidad/propiedad del nombre exacto. Una respuesta
   403 de S3 no demuestra disponibilidad. Si hay colisión, detenerse y pedir
   autorización; no generar un nombre alternativo ni importar un bucket ajeno.
3. Un administrador autorizado usa credenciales temporales para inicializar esta
   raíz independiente y revisar su plan con `account_id` explícito. Solo después
   de aprobación puede aplicar. Estos pasos NO se ejecutaron.
4. Conservar el estado local del bootstrap y sus backups en almacenamiento seguro,
   con acceso restringido, separado de EKS y fuera de Git. Registrar custodio y
   procedimiento de recuperación. No migrarlo al mismo bucket que administra.
5. Comprobar bloqueo público, propiedad BucketOwnerEnforced, SSE-S3, versionado y
   denegación HTTP antes de permitir estados. No hay force_destroy ni lifecycle
   de expiración de versiones. El bootstrap no crea OIDC, roles, redes ni EKS.

Cada root EKS usará su propio key `states/<teamId>/aws/<environment>/<instance>/terraform.tfstate`.
Ejemplo aprobado de estructura: `states/D001/aws/dev/eks-01/terraform.tfstate`.
Copiar backend.hcl al root, añadir `allowed_account_ids` con la cuenta aprobada y
un bloque backend S3 en ese root solo con autorización para ese repositorio.
Usar únicamente workspace Terraform `default`; no cambiar prefijos vía workspaces.
El lock es el objeto `.tflock`, sin DynamoDB. Nunca usar `-lock=false`.

## IAM y OIDC antes de activar

Crear o reutilizar, previa revisión, el proveedor `https://token.actions.githubusercontent.com`
con audiencia `sts.amazonaws.com`. Crear roles distintos por equipo, ambiente,
instancia y fase: plan, apply y destroy. Los nombres IAM están pendientes de
aprobación; no se generan nombres alternativos a la nomenclatura existente.

Instanciar la confianza con cuenta y `sub` EXACTOS de cada environment, sin comodines.
Verificar el formato real: GitHub puede usar sujetos inmutables con IDs de
repositorio/propietario; no asumir el formato histórico basado solo en nombres.
No capturar ni publicar el JWT. Validar los claims en una sesión de diagnóstico
controlada sin registrar tokens. Las condiciones aud y sub deben usar StringEquals.

La política JSON de estado permite ListBucket con prefijos exactos, Get/Put solo
sobre el estado de la instancia y Get/Put/Delete sobre su lock. No permite borrar
estado, versiones ni bucket. No adjuntar permisos administrativos S3 a roles de CI.
Replicar con revisión para cada instancia. Auditar políticas adicionales, límites
organizacionales y accesos entre cuentas: esta política sola no restringe otros
grants existentes. El rol plan necesita escritura del lock y no debe recibir
permisos de modificación de recursos EKS.

Falta la política de recursos EKS: derivarla del módulo SHA aprobado y del inventario
de recursos/ARNs real; usar recursos exactos, condiciones de tags cuando la API lo
soporte y iam:PassRole solo sobre roles autorizados y servicios concretos. Documentar
las APIs de lectura que requieran Resource `*` individualmente. No otorgar por
comodín permisos EC2/IAM/EKS. No conceder modificaciones de Security Groups ni reglas
110–502. Si el módulo las necesita, reportar el bloqueo antes de alterar el módulo
o ampliar permisos. Apply/destroy permanecen inoperables hasta esta revisión.

## Activación en platform-engineering-devs

- Confirmar propietario/ID de repo, cuenta, roles, paths, versión Terraform y SHA
  real de 40 hex del módulo en `platform-engineering-vars-tfc`. Verificar cada
  source con `?ref=<SHA>`; no usar branches/tags. No se inventó un SHA ni módulo.
- Resolver Networking completo y autorización: VPC/subnets/CIDR y conformidad
  revisadas, sin inventar valores. Validar inputs reales del root y sus pruebas.
- Añadir lockfile de proveedores revisado. Las ejecuciones usan `-lockfile=readonly`.
  Si el repo de módulos es privado, definir acceso GitHub de lectura por GitHub App
  efímera o mecanismo aprobado; no introducir PAT ni credenciales AWS permanentes.
- Revisar las acciones fijadas por SHA y su procedencia/compatibilidad antes de
  copiarlas. Configurar CODEOWNERS, protección de main y revisión obligatoria de
  workflows, módulos, backend y archivos de red. Prohibir bypass administrativo.
- Crear environments `D001-dev-eks-01-plan`, `D001-dev-eks-01-apply` y
  `D001-dev-eks-01-destroy`, todos limitados a main y con revisores requeridos,
  prevent self-review y sin bypass. El environment plan autoriza el plan; un
  revisor independiente del solicitante debe revisar el artefacto review.txt y
  aprobar apply/destroy. Verificar que el plan de GitHub permite estas protecciones;
  si no, mantener bloqueado. IAM no prueba por sí solo la independencia humana.
- Variables por environment: AWS_ACCOUNT_ID y AWS_PLAN_ROLE_ARN o
  AWS_EXECUTION_ROLE_ARN según fase. NETWORKING_APPROVED y AUTOMATION_ENABLED deben
  ser `true` en plan únicamente tras autorización. No usar variables de PR como
  identidad ni habilitar pull_request_target. Validate no tiene OIDC ni secretos;
  usar runners efímeros hospedados, nunca runners con credenciales heredadas.
- Sustituir REPLACE_OWNER, adaptar path y confirmar el backend exacto. Solo una PR
  de activación explícitamente aprobada puede retirar el `exit 1` incondicional.
  Copiar las plantillas a `.github/workflows/*.yml` únicamente en el repo destino.
- Destroy requiere además escribir `destroy D001/aws/dev/eks-01`; no sustituye la
  aprobación del environment ni una autorización operativa explícita.

La exclusión mutua cubre plan y ejecución por instancia. El artefacto del mismo
run/attempt contiene plan binario, SHA256, commit e instancia; apply verifica todo
antes de obtener credenciales y aplica ese binario, sin recalcular. Terraform
rechaza planes obsoletos si el estado cambia. Tras fallo o expiración generar otro
plan y repetir ambas aprobaciones. No reintentar solo apply desde otro artefacto.
Los planes y review.txt pueden contener secretos: acceso restringido al repo,
retención de un día y eliminación al cerrar la operación. El hash detecta cambios;
la procedencia depende además de GitHub Artifacts y la protección de workflows.

## Vault futuro

No desplegar Vault ahora. Diseño pendiente: GitHub OIDC contra auth JWT de Vault,
con audience propia, issuer, repositorio y environment ligados por claims exactos;
políticas Vault por instancia/fase y TTL corto. El secrets engine AWS emitirá
credenciales STS temporales para los mismos roles y límites de IAM. Resolver el
bootstrap de confianza Vault→AWS sin access keys permanentes antes de activarlo.
Configurar HTTPS verificado, auditar leases y revocación, enmascarar valores y
entregar credenciales solo por entorno del job; nunca tfvars, backend.hcl o
artefactos. Sustituir el paso OIDC→AWS después de pruebas y autorización, sin cambiar
contratos de Backstage/Orchestrator/Terraform Agent. `.env` local sigue fuera de Git;
no se leyó ni modificó y no debe cargarse en CI.

## Cierre del laboratorio y eliminación del bucket

1. Bloquear nuevos jobs y solicitudes; inventariar todos los keys, versiones,
   delete markers y locks de todos los equipos. No borrar nada todavía.
2. Destruir infraestructura con planes y aprobaciones independientes por instancia;
   comprobar inventario AWS y estados vacíos. Un estado vacío por sí solo no prueba
   ausencia de recursos; reconciliar recursos huérfanos. Resolver locks solo tras
   confirmar que no existen operaciones activas.
3. Exportar estados/versiones y estado del bootstrap a custodia segura con checksum
   y política de retención aprobada; verificar recuperación. Obtener autorización
   explícita para borrar datos históricos y bucket con inventario adjunto.
4. En una revisión de cierre autorizada, retirar prevent_destroy del bootstrap.
   Mantener force_destroy=false. Un administrador distinto de los roles CI elimina
   explícitamente las versiones, delete markers y uploads multipart pendientes del
   bucket exacto, después de comprobar cuenta y nombre. No usar borrado recursivo
   como prueba ni eliminar antes de obtener autorización.
5. Revisar y aprobar el plan de destrucción del bootstrap con su estado independiente;
   ejecutar únicamente al estar vacío. Verificar eliminación y archivar evidencias.
   Revocar roles/confianzas exclusivos del laboratorio; no borrar un proveedor OIDC
   compartido. El nombre liberado puede ser adquirido por terceros: retirar referencias.

## Verificación local

`python3 -m unittest discover -s aws/dev/eks/automation/terraform-aws/tests -v`

`terraform fmt -check -recursive aws/dev/eks/automation/terraform-aws`

No ejecutar plan/apply/destroy ni pruebas con proveedor real durante esta preparación.
Las pruebas Python verifican barreras y alcance de políticas, no simulan AWS ni
certifican permisos, integración GitHub, comportamiento del proveedor o disponibilidad.
Validación semántica y pruebas mock de Terraform quedan pendientes de Terraform >=1.10,
proveedores revisados y herramientas disponibles; no se instala software automáticamente.

Referencias oficiales:
- https://developer.hashicorp.com/terraform/language/backend/s3
- https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws
- https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment
