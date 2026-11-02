# Auditoría técnica previa a activación — 2026-11-02

Resultado: NO APTO PARA ACTIVACIÓN. Las plantillas siguen inactivas y bloqueadas.
Se revisaron únicamente archivos locales; no se consultaron AWS ni la configuración
remota de GitHub. Severidades consideran el escenario de futura activación; no se
observó exposición AWS activa. Referencias de línea corresponden a esta revisión.

## Alta — A1. Backend y rol no vinculados a una configuración confiable

Ubicación: templates/apply.yml.template:44, :53, :92, :96, :104;
templates/destroy.yml.template:48, :57, :96, :100, :108;
templates/backend.hcl:1–6; iam/state-D001-dev-eks-01.json:9–34.

No hay inputs dispatch para seleccionar rol/bucket/key: Destroy solo recibe una
confirmación. Los roles provienen de variables GitHub, no del formulario del
desarrollador. Sin embargo, backend.hcl y el root Terraform son código modificable
por contribuyentes. Un cambio aprobado/mezclado podría cambiar bucket/key, añadir
assume_role al backend/proveedor o usar otro backend. approved.instance es una
etiqueta literal; no se deriva del backend y por tanto no prueba su correspondencia.
allowed-account-ids del action no verifica el bucket ni todos los roles asumidos
posteriormente por Terraform. El backend aún no limita la cuenta.

La política S3 suministrada no concede acceso a otros equipos. Es una política
Allow parcial: otras políticas identity/resource, grants entre cuentas o permisos
sts:AssumeRole podrían ampliar acceso. Tampoco limita el código que se ejecuta
con credenciales. No puede certificarse aislamiento efectivo desde esta plantilla.

Propuesta pendiente de aprobación: configuración administrada por Platform con
cuenta, roles, bucket/key y SHA autorizados; verificar backend efectivo y sources,
impedir roles/backend alternativos y restringir IAM efectivo a la instancia.
Revisar policies/boundaries/bucket policy y negar escalamiento no autorizado;
CODEOWNERS y protección de main sin bypass para root/backend/workflows. No basta
con añadir flags CLI si el root puede cambiar arbitrariamente.

## Alta — A2. Aprobaciones y confianza solo declaradas, no verificadas

Ubicación: templates/apply.yml.template:13, :70;
templates/destroy.yml.template:17, :74; iam/trust.json.template:7–13;
README.md:91–106.

Los jobs mencionan environments pero no configuran required reviewers, prevent
self-review, restricciones de rama o bypass. No hay export de settings/rulesets
remotos para auditarlos. Sin esas protecciones el job podría empezar sin revisión.
El sub exacto y aud son un patrón correcto pero tienen placeholders; no existen
roles verificados. Un sub de environment por sí solo no identifica el workflow:
otro workflow autorizado a usar ese environment podría asumir el mismo rol.
OIDC tampoco certifica que se haya revisado un plan concreto. Prevent self-review
impide aprobar al iniciador; no fuerza que el revisor de plan difiera del revisor
de apply/destroy. Listar varios reviewers requiere solo uno, no unanimidad.

Propuesta pendiente: configurar y exportar settings de los tres environments,
main exclusiva, revisores por fase, prevent self-review y bypass deshabilitado;
limitar administradores que pueden editar variables/reglas y proteger todo workflow
que use esos environments. Si se exige segregación entre revisores de fases,
usar equipos disjuntos o una regla de protección independiente. Evaluar sujeto
OIDC ligado también al workflow confiable según capacidades reales de GitHub/AWS;
no inventar claims. Probar rechazos tras autorización en entorno controlado.

## Alta — A3. Validate ejecutaba pruebas potencialmente operativas — corregido

Ubicación original: templates/validate.yml.template:24.
Ubicación actual: templates/validate.yml.template:22–25; tests/test_safety.py:45.

terraform test puede crear y destruir infraestructura; un run usa apply por defecto.
Sin OIDC/secrets el riesgo de AWS se reduce, pero no garantiza pruebas offline ni
impide acceso a otros sistemas. Se retiró la invocación genérica. Se conserva fmt,
init sin backend y validate, con lockfile readonly y salida inmediata ante errores.
Nueva regresión comprueba que Validate no ejecute terraform test ni dependa de
Networking. Las pruebas mock específicas siguen pendientes de una suite revisada;
no se afirma que se ejecuten pruebas de módulos EKS.

## Media — M1. Terraform local incompatible; versiones y lockfile pendientes

Ubicación: bootstrap/main.tf:2–6; templates/validate.yml.template:17;
templates/apply.yml.template:41, :86; templates/destroy.yml.template:45, :90.

Comprobado: Terraform 1.5.7 darwin_arm64. use_lockfile requiere >=1.10.
Las plantillas fijan 1.10.5, compatible con esa función pero una base antigua.
Recomendación: evaluar y fijar Terraform 1.17.1, publicado como estable en el índice
oficial consultado; confirmar compatibilidad del módulo y proveedor con validate
sin backend y pruebas mock antes de adoptarlo. Usar la misma versión exacta en
plan/apply/destroy y estaciones autorizadas. No se actualizó binario ni plantilla.

No hay .terraform.lock.hcl del bootstrap; ~>6.0 admite cambios de proveedor 6.x.
Generar/revisar lockfile para plataformas local/CI, sin actualizar módulos EKS.
Validate usa readonly: si falta lockfile fallará de forma deliberada. Los SHA de
acciones están fijados pero su existencia/procedencia no quedó certificada por
esta auditoría; verificar cada commit antes de activar.

## Media — M2. Integridad del plan parcial; revisión humana externa

Ubicación: templates/apply.yml.template:55–65, :82–105;
templates/destroy.yml.template:59–69, :86–109.

Comprobado estáticamente: apply consume únicamente approved.tfplan; no recalcula
el plan, no acepta run/artifact ID externo, descarga nombre del mismo run/attempt,
comprueba checksum/commit/etiqueta de instancia y usa checkout del commit del evento.
Destroy genera -destroy y exige texto exacto antes del plan más environment distinto.
Ambos comparten concurrency por instancia; lock S3 actúa como defensa adicional.

Límites: checksum, commit e instancia viajan en el mismo artefacto; no son firma ni
atestación independiente. review.txt no está incluido en checksum. No hay vínculo
mecánico entre digest del plan y decisión del revisor; el environment depende de
que este inspeccione el artefacto correcto. approved.* es un glob amplio: un archivo
extra versionado podría publicarse. El rechazo de planes obsoletos de Terraform
protege cambios de estado, no reemplaza revisión de drift ni autorización.

Propuesta pendiente: lista explícita de archivos, manifest generado con digest de
plan y review.txt, operación, backend y SHA del módulo verificados; mostrar digest
y run en el resumen de aprobación. Si se exige prueba formal de aprobación por
digest, diseñar un control de protección/atestación separado. Mantener artefactos
sensibles en repo privado con acceso limitado; un día de retención no restringe
quién puede leerlos durante ese período.

## Media — M3. Permisos AWS y barreras efectivas incompletos

Ubicación: iam/state-D001-dev-eks-01.json:4–34; bootstrap/main.tf:26–81;
README.md:70–76.

La política de estado contiene Get/Put sobre key exacto y Get/Put/Delete sobre
.tflock. No hace falta DeleteObject sobre el estado ni KMS para SSE-S3. No añadir
ListBucket global para silenciar errores: Terraform 1.10.5 intenta listar env:/
y su código tolera AccessDenied con el prefijo default; verificar ese comportamiento
si se cambia versión/backend. Las operaciones necesarias sobre la key exacta están
permitidas. No se probó contra S3.

Faltan roles/trust instanciados y permisos para lectura de recursos en plan,
operaciones EKS/recursos asociados en apply/destroy e iam:PassRole acotado si el
módulo lo usa. El inventario definitivo requiere módulo SHA y red aprobados; no se
ha inventado una política EKS. STS AssumeRoleWithWebIdentity depende de trust, no
de access keys GitHub. Restringir saltos posteriores por sts:AssumeRole.

Bootstrap requiere un administrador temporal separado con acciones S3 de creación,
lectura y configuración de bucket, public access block, ownership controls,
versioning, encryption, policy y tags según el proveedor elegido. El cierre requiere
ListBucketVersions/DeleteObjectVersion y permisos de eliminación del bucket además
de revisión de multipart uploads. Ninguno debe darse por defecto a CI de EKS.
Determinar acciones exactas con versión del proveedor antes de aplicar.

No existe una prohibición IAM efectiva de cambios a Security Groups en estos
archivos; no hay permisos de recursos definitivos. Antes de activar revisar todos
los grants y evaluar un deny explícito/boundary para preservar reglas 110–502,
sin editar SG ni módulos. Política final pendiente de autorización.

## Baja — B1. Protecciones locales no equivalen a garantías AWS

Ubicación: bootstrap/main.tf:10, :28–34, :38–81.

El bootstrap es independiente, usa nombre exacto/región requerida, SSE-S3,
versionado, bloqueo público, BucketOwnerEnforced y deny de transporte inseguro.
prevent_destroy protege mientras exista la configuración; no impide borrado manual
ni su retirada en una revisión. force_destroy=false evita vaciado automático.
El estado local necesita custodia y backup seguro. SSE-S3 por defecto no constituye
por sí solo una regla que rechace cualquier algoritmo alternativo enviado por
un escritor autorizado; considerar enforcement si ese es el requisito estricto.
El nombre global no fue consultado y no se generaron alternativas.

## Controles operativos comprobados y límites

- Networking: apply:30–38 y destroy:34–42 verifican variables y siempre terminan
  antes del action AWS. Ningún workflow está instalado en .github/workflows.
- Validate no tiene OIDC ni pasos AWS, no consulta Networking y permite preparar
  validaciones de PR; no hay workflow/regla que bloquee publicar PR. No se publicó.
- Los tests locales son regresiones de contenido; no certifican ejecución de
  GitHub Actions, autorización AWS, protecciones remotas ni integración EKS.
- Ninguna herramienta fue actualizada. No hubo AWS, init remoto, plan, apply,
  destroy, commit, push ni cambios en módulos EKS, SG, contratos, Backstage o agentes.

## Referencias oficiales consultadas

- https://releases.hashicorp.com/terraform/ — versiones disponibles.
- https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/backend.html — lock nativo desde 1.10.
- https://developer.hashicorp.com/terraform/language/tests — pruebas y apply por defecto.
- https://developer.hashicorp.com/terraform/language/backend/s3 — permisos estado/lock.
- https://raw.githubusercontent.com/hashicorp/terraform/v1.10.5/internal/backend/remote-state/s3/backend_state.go — listado de workspaces y AccessDenied.
- https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments — revisores y protecciones.
- https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws — confianza aud/sub y environments.
