# Reorganización aprobada — 2026-11-02

Resultado: reorganización y validación local completadas. Checkout central:
`.`.
Listo para revisar el contenido del primer commit como versión draft/inactiva;
no se hizo stage, commit, push ni publicación de PR.

## Movimientos y referencias

El mapa completo y el árbol están en STRUCTURE.md. Los antiguos directorios raíz
terraform/ y automation/ ya no existen. Todos sus componentes centrales quedaron
bajo aws/dev/eks/. Catálogo único de esta composición: aws/dev/eks.yaml, intacto.
El archivo preexistente aws/dev/kubernetes.yaml no se modificó ni se usa como
fallback del generador.

- modules/aws y modules/naming conservan su contenido exacto.
- templates/tools usan la raíz aws/dev/eks y leen ../eks.yaml y naming/aws.json.
- Los ocho sources Git usan //aws/dev/eks/modules/... y SHA inmutable. Ejemplo y
  contexto mantienen <SHA_REAL>; el token interno @@MODULE_SHA@@ se renderiza.
- Composición genérica: examples/composition, sources ../../modules/ y catálogo
  ../../../eks.yaml. No hay cambios en sus gates ni recursos.
- Tests Python/Node/HCL apuntan a las nuevas rutas. Las pruebas estáticas del
  antiguo D001 inspeccionan el ejemplo ilustrativo, no un workspace central.
- Documentación, procedimientos y comandos usan el nuevo prefijo.
- Automation conserva backend, políticas, bloqueos y workflows .template inactivos.
  El destino de los jobs sigue siendo el repo platform-engineering-devs.

No se eliminó el antiguo ejemplo D001: se archivó fuera del checkout en
`directorio externo de respaldo (former-workspace-examples)`.
Su prueba HCL negativa se conserva como plantilla bajo tests/fixtures y se
materializa junto al root temporal de integración. No se ejecutaron planes mock.
Los caches .terraform también quedaron fuera del repositorio para no conservar
manifiestos con paths obsoletos. El mirror local del proveedor se reutilizó allí.

## Integridad comprobada

Comparación SHA256 antes/después:

- aws/dev/eks.yaml idéntico: bd96ec38c9cee68e608a21cb75427c6f1fc2b26deac099fcb7bb1f23bc6fd760.
- 42 archivos de módulos idénticos byte a byte, incluidos SG y documentación de módulos.
- naming/aws.json idéntico.
- No existen workspaces, estados Terraform, snapshots de catálogo generados ni
  workflows activos dentro del checkout central.

El manifiesto reorganization-checksums.json contiene las huellas para revisión.
El catálogo ya figuraba modificado respecto de HEAD antes de esta tarea; se conservó
ese borrador exactamente. Esa modificación previa no proviene de la reorganización.

## Validación ejecutada

- 12 pruebas Node del generador: PASS.
- 17 pruebas Python existentes de naming y estructura: PASS.
- 5 pruebas de automatización: PASS.
- terraform fmt -check -recursive aws/dev/eks: PASS.
- YAML de Validate/Apply/Destroy: PASS.
- git diff --check y comprobación explícita de whitespace de archivos nuevos: PASS.
- Terraform validate con proveedor local 6.20.0:
  - D001: 0 errores, 0 advertencias.
  - D002: 0 errores, 0 advertencias.
  - Composición genérica: 0 errores, 0 advertencias.
  - Bootstrap: 0 errores, 0 advertencias.

Se usó Terraform 1.11.4 ya disponible; no se actualizaron herramientas.
D001/D002 se generaron únicamente en:
`generated/platform-engineering-devs/workspaces/`.
Los sources Git se sustituyeron por rutas locales únicamente en otras copias
temporales de validación. Se usó mirror local exclusivo, lockfile readonly y
backend=false. La carga del esquema del proveedor se ejecutó fuera del sandbox,
con autorización. No se configuró el proveedor contra AWS ni se evaluaron data
lookups. No hubo plan/apply/destroy ni descarga Git.

## Bloqueos y compatibilidad

1. Los antiguos sources //terraform/modules/... ya no son válidos para el futuro
   commit reorganizado. Usar el nuevo prefijo y el SHA del commit correspondiente;
   el transporte Git se validará después de publicar, sin inventar un SHA.
2. Caches antiguos no deben copiarse al nuevo árbol; inicializar sin backend con
   mirror local para pruebas. Lockfiles existentes se conservaron.
3. El renderer sigue dependiendo de yaml (disponible en Backstage mediante
   NODE_PATH); acordar empaquetado antes de ofrecer una herramienta autónoma.
4. El checkout y sus archivos auxiliares están en temporales: acordar custodia
   durable antes de limpiar un directorio temporal. No mover repositorios externos por iniciativa.
5. Networking sigue pending en catálogo y plantilla; módulos AWS del draft a count=0,
   precondition NETWORKING_PENDING y exit 1 de los workflows intactos. Generar archivos
   funciona; publicar PR requerirá la integración futura, no implementada aquí.
6. AWS permanece bloqueado además por red, parámetros operativos, aprobaciones,
   IAM/OIDC efectivo y controles del backend pendientes. Publicar módulos inactivos
   no autoriza aplicar infraestructura ni crear s3ue1p001dev01.

No se modificó Backstage, Orchestrator, Terraform Agent ni sus contratos. La copia
histórica en Backstage no se tocó; la ubicación central de revisión es aws/dev/eks/.
