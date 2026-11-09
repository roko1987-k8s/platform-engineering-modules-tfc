# Módulos autorizados de Platform Engineering

Repositorio central de módulos Terraform y plantilla EKS para generación por
Terraform Agent. No contiene workspaces de equipos, estados, planes, credenciales,
fixtures, ejemplos de laboratorio ni resultados internos de pruebas.

## Componentes operativos

- `aws/dev/main.tf`: plantilla principal EKS con tokens; requiere renderizado.
- `aws/dev/eks.yaml`: catálogo autorizado; Networking continúa pendiente (Terraform crea VPC/subnets cuando Networking asigne los CIDR; ver `aws/dev/eks/README.md`).
- `aws/dev/eks/modules/`: ocho módulos de la composición EKS, incluido naming.
- `aws/dev/eks/naming/aws.json`: política que el generador incorpora al workspace.
- `aws/dev/eks/tools/render-eks-pure.cjs`: renderizado en memoria, sin I/O ni procesos.
- `aws/dev/eks/tools/render-eks.cjs`: adaptador local; formato explícito y opcional.
- `aws/dev/eks/tools/render-eks.test.cjs`: pruebas sin fixtures ni artefactos.
- `aws/dev/s3/modules/s3/` y `aws/dev/s3/bootstrap/`: módulo reutilizable y raíz
  independiente con backend local. Ver `aws/dev/s3/README.md`.
- `aws/dev/iam/modules/github-oidc/`: roles por fase con proveedor OIDC existente.
  Ver su README para entradas obligatorias y bloqueo de aprovisionamiento.
- `github-actions/`: plantillas inactivas separadas por Validate, Apply y Destroy.
- `tools/terraform/validate-offline.py`: validación operativa sin fixtures ni AWS.
- `azure/dev/aks.yaml`: catálogo preexistente de Azure, conservado sin cambios.

Las rutas son relativas a la raíz del repositorio. Los módulos son independientes;
no se fusionan main.tf ni se copian módulos dentro de los workspaces generados.

## Generación EKS

El llamador proporciona contexto y selección autorizados en archivos externos:

```sh
node aws/dev/eks/tools/render-eks.cjs "$CONTEXT_FILE" "$SELECTION_FILE" "$OUTPUT_ROOT"
```

El renderizado requiere Node y el paquete `yaml` disponible en el entorno del
llamador. No requiere Terraform. El formato anterior solo se solicita con
`formatRendered(result)` o `--format` al final de la CLI, fuera de preview;
únicamente esa opción requiere un binario Terraform, seleccionable mediante
TERRAFORM_BIN. La CLI escribe un workspace y no forma parte del camino preview.
Ver `aws/dev/eks/README.md` para el contrato. Este repositorio no empaqueta yaml;
no se instala ni actualiza ninguna dependencia automáticamente.

## Validación offline

No ejecutar Terraform directamente en `aws/dev/`: main.tf contiene tokens.
El formato se comprueba únicamente en los módulos y bootstrap:

```sh
terraform fmt -check -recursive aws/dev/eks/modules aws/dev/s3 aws/dev/iam/modules
python3 tools/terraform/validate-offline.py --terraform-bin "$TERRAFORM_BIN" --provider-mirror "$TERRAFORM_PROVIDER_MIRROR" --lockfile "$REVIEWED_PROVIDER_LOCKFILE"
```

El validador requiere herramientas ya instaladas, un mirror local y un lockfile
existente revisado que seleccione AWS 6.20.0. El mirror debe contener el paquete
completo compatible con sus checksums; no regenerar el lock si no coincide. Usa copias temporales fuera del
repositorio, backend=false y lockfile=readonly; no descarga providers, no cambia
restricciones ni modifica el lockfile de entrada. No ejecuta plan/apply/destroy ni
pruebas que creen recursos. Una dependencia ausente es un bloqueo, no autorización
para descargarla o actualizarla. Para comprobar solo el renderer, sin Terraform:

```sh
NODE_PATH="$RENDERER_NODE_MODULES" node --test aws/dev/eks/tools/render-eks.test.cjs
```

La prueba se incluye junto a la herramienta por solicitud explícita de revisión
y publicación manual; no contiene fixtures ni genera artefactos. Otros ensayos y
fixtures siguen fuera del árbol publicable.

## Versiones conservadas

| Componente                            | Restricción Terraform existente | AWS provider existente                  |
| ------------------------------------- | ------------------------------- | --------------------------------------- |
| Siete módulos AWS de EKS              | >= 1.9.0, < 2.0.0               | = 6.20.0                                |
| Naming EKS, declarado en terraform.tf | >= 1.9.0, < 2.0.0               | Ninguno                                 |
| Plantilla principal EKS               | >= 1.10.0, < 2.0.0              | = 6.20.0                                |
| S3, bootstrap e IAM/OIDC              | >= 1.10, < 2.0                  | ~> 6.0                                  |
| Plantillas Actions                    | 1.10.5                          | Según lockfile del workspace consumidor |

Estas diferencias no se sincronizan ni se cambian durante una limpieza. Cada
módulo conserva sus archivos de configuración existentes. Naming mantiene su
terraform.tf original; no se agrega una declaración duplicada. Los consumidores
necesitan locks revisados antes de ejecutar; no se publica un lock de laboratorio
como si fuera el del bootstrap o de un workspace real.

## Límites operativos y publicación

Networking pendiente, count=0, precondición NETWORKING_PENDING y bloqueos Actions
se mantienen. Completar Networking no autoriza despliegue: faltan procedencia de
SHA, parámetros de ejecución, compatibilidad de versiones/AMI/add-ons, red real,
KMS/volúmenes, permisos mínimos y aprobaciones. No se modifican SG ni reglas 110–502.
La plantilla no representa por sí sola una validación integral de todos esos gates.

D001/eks-01 en las plantillas Actions y backend.hcl son un destino específico, no
una selección genérica de equipos. El renderer parametriza equipo y secuencia,
pero conserva dev y el bucket central aprobados. S3 conserva P001/dev como identidad
de infraestructura central; IAM deriva el alcance desde entradas usando el documento
original. Cambiar estos comportamientos requiere una revisión independiente.

Las ocho referencias Git de la plantilla EKS se preparan para
`roko1987-k8s/platform-engineering-modules-tfc`, conservando subdirectorios y
`@@MODULE_SHA@@`. Las referencias ajenas a EKS se conservan. El contexto requiere
un SHA real verificado; el token no es una referencia ejecutable. Después de la
publicación manual, verificar el commit remoto y fijar SHA/digests en los
consumidores autorizados, incluyendo los nuevos archivos del renderer puro.
No se modifican remotos Git, historial ni consumidores externos.
La revisión histórica de privacidad sigue siendo independiente; esta tarea no
reescribe historial, hace commit/push ni activa infraestructura.
