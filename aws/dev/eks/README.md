# Composición EKS para Terraform Agent — bloqueada

Rutas de este documento relativas a la raíz del repositorio. Catálogo autorizado:
`aws/dev/eks.yaml`. Plantilla principal: `aws/dev/main.tf`. Ocho módulos permanecen
en `aws/dev/eks/modules/`: networking, IAM, security-groups, EKS, nodegroups,
add-ons, observability y naming. Las fuentes Git de la plantilla EKS apuntan a
`roko1987-k8s/platform-engineering-modules-tfc` y conservan sus rutas y contratos.
Observability permanece disponible como módulo independiente; la plantilla actual
no lo invoca. Addons se utiliza en dos fases; no se añade wiring nuevo.

## Contrato de generación

`aws/dev/eks/tools/render-eks.cjs` exporta `render(context, selection)` sin formato y una CLI:

```sh
node aws/dev/eks/tools/render-eks.cjs "$CONTEXT_FILE" "$SELECTION_FILE" "$OUTPUT_ROOT"
```

El contexto contiene exactamente teamId, environment, sequence y moduleSha. El
llamador autorizado resuelve identidad, ambiente, secuencia y SHA; no son campos
libres del developer. El renderer actual admite dev, códigos de equipo canónicos
y secuencias de 1 a 99. Comprueba la forma del SHA, no su existencia o procedencia:
el llamador debe verificar que sea un commit real con módulos autorizados.

La selección contiene exactamente system y user, cada uno con size,
minimum, desired y maximum. Se respetan tamaños y límites del catálogo sin mapas
EC2 alternativos. La política `aws/dev/eks/naming/aws.json` es una dependencia de
generación, no un catálogo alternativo. El paquete Node yaml debe estar disponible
en el entorno del llamador.

`aws/dev/eks/tools/render-eks-pure.cjs` exporta `renderPure(context, selection, sources)`.
`sources` contiene `catalogBytes`, `namingBytes` y `template`, procedentes de las
fuentes autorizadas anteriores. Devuelve strings en memoria: no lee archivos,
no escribe workspaces y no ejecuta procesos. El llamador conserva la obligación
de verificar SHA, procedencia, identidad y autorización antes de consumirlo.
`render` es solo el adaptador de lectura de esas fuentes locales existentes.

El formato es una operación explícita separada: `formatRendered(result)` devuelve
una copia formateada o la CLI admite `--format` como último argumento.
Solo esa opción ejecuta `terraform fmt -` para main.tf y backend.hcl;
`TERRAFORM_BIN` selecciona el binario existente. El camino de preview debe usar
exclusivamente `renderPure`, sin invocar el formateador ni la CLI que escribe.
El cambio de valor predeterminado es intencional: consumidores que necesiten el
formato anterior deben solicitarlo explícitamente fuera de preview.

El resultado contiene workspace y cinco archivos: main.tf, backend.hcl,
catalog.snapshot.json, naming.snapshot.json y generation.json. La ruta deriva
como `workspaces/<teamId>/terraform/<cloud>/<environment>/<instance>` con cloud=aws
e instance construida con el prefijo eks y la secuencia de dos dígitos. La CLI no
sobrescribe directorios con contenido. Las instantáneas son entradas del workspace,
no nuevas fuentes centrales. Las pruebas y ejemplos no son dependencias del renderer.

El backend generado conserva el bucket central y deriva la key del equipo,
ambiente e instancia. No ejecuta init, plan, apply, AWS ni publicación de PR.
La plantilla principal contiene tokens y no se ejecuta directamente desde aws/dev.

## Gates y validación

Networking continúa pending. El renderer rechaza catálogos con red ya aprobada;
la plantilla conserva módulos AWS con cero instancias y NETWORKING_PENDING.
Estos controles no garantizan ausencia de acceso remoto si alguien inicializa un
backend o configura un proveedor con credenciales fuera del flujo autorizado.

Antes de habilitar ejecución se requieren red y conectividad aprobadas,
procedencia/digest del catálogo y módulos, releases AMI, volúmenes/KMS, retención,
versiones/propiedad de add-ons, revisión de SG administrados y flujos autorizados,
permisos mínimos y aprobaciones independientes. El draft no sustituye esas revisiones.
No cambiar Security Groups ni reglas 110–502 para desbloquearlo.

La validación operativa y restricciones de versiones se documentan en README.md
de la raíz. Las pruebas del renderer incluidas para revisión/publicación manual
se ejecutan sin fixtures, archivos de salida, red ni Terraform:

```sh
NODE_PATH="$RENDERER_NODE_MODULES" node --test aws/dev/eks/tools/render-eks.test.cjs
```

`RENDERER_NODE_MODULES` referencia dependencias ya instaladas y revisadas que
contengan `yaml`. Si el entorno ya lo resuelve, puede omitirse NODE_PATH.
No se instala ninguna dependencia. El formateador se prueba con un mock; la CLI
de escritura y Terraform no se ejecutan. Otros ensayos/fixtures siguen fuera del
árbol publicable.

## Referencias pendientes después de publicar manualmente

`@@MODULE_SHA@@` permanece en la plantilla: es un token, no un SHA remoto inventado.
El renderer continúa exigiendo `context.moduleSha` de 40 caracteres hexadecimales.
Tras publicar manualmente, comprobar en remoto el commit elegido y las rutas EKS
antes de suministrar ese SHA desde un contexto autorizado. No usar main como pin,
sustituir el token por un marcador ficticio ni fijar el SHA dentro del renderer.

Fijar por separado los commits del catálogo/composición y sus digests revisados:
YAML original, snapshot JSON canónico, plantilla, naming y renderer puro. Un cambio
de plantilla o renderer requiere recalcular sus digests. Esta preparación local no
acredita el futuro commit publicado, ni concede permisos o aprobaciones.

El catálogo EKS mantenido aquí continúa en `aws/dev/eks.yaml`, sin cambios de
contenido. Esta consolidación solo modifica este repositorio. Los consumidores
externos que fijan `platform-engineering-vars-tfc/aws/dev/eks.yaml` necesitan una
revisión separada de su fuente y pins; no se implementa un fallback ni se modifican
Orchestrator, Terraform Agent o Backstage en esta tarea.


## Modos de ejecución y Networking

`proposal_mode` (en el `main.tf` del workspace) admite:

| Modo | Qué crea | Entradas de `reviewed_execution` requeridas |
|---|---|---|
| `DESIGN_WITHOUT_AWS_ACCOUNT` (default) | Nada; `NETWORKING_PENDING` bloquea el plan | — |
| `NETWORKING_ONLY` | VPC, subnets públicas/privadas, IGW, NAT, rutas | `aws_account_id`, `networking` |
| `EKS_CLUSTER` | Lo anterior + IAM del clúster, SG, EKS, add-ons, node groups | además `resource_prefix`. Opcionales (con `null` se usan los valores por defecto de AWS): `kms_key_arn`, `log_retention_days`, `root_volumes`, `release_versions`; `deletion_protection` (por defecto `true`) |

`networking` es el objeto único asignado por Networking:

```hcl
networking = {
  vpc_cidr             = "<asignado por Networking>"
  public_subnet_cidrs  = ["<asignado>"]               # uno por NAT Gateway
  cluster_subnet_cidrs = ["<asignado>", "<asignado>"]
  node_subnet_cidrs    = ["<asignado>", "<asignado>"]
  approval_reference   = "<ticket de aprobación>"
  connectivity         = null # se atestigua cuando la VPC ya existe
}
```

- Se mantiene dentro de `reviewed_execution` porque el Terraform Agent verifica el
  conjunto exacto de variables de esta raíz.
- Región: `var.region`, validada contra `aws/dev/eks.yaml`; provider y AZ deben
  pertenecer a ella. Reparto determinista en al menos dos AZ.
- Nombres: `module.naming` (`names.vpc`, `subnet_names`). Tags `Team`,
  `ApplicationCode` y `Environment` desde las entradas autorizadas, en el
  networking y en todos los recursos del clúster que admiten tags.
- Gates (`terraform_data.networking_gate`, solo más estrictos):
  `NETWORKING_PENDING` sin red aprobada y `EXECUTION_INPUT_INCOMPLETE` en
  `EKS_CLUSTER`. `terraform_data.account_gate` rechaza credenciales de otra
  cuenta (`ACCOUNT_MISMATCH`).
- Plan, Apply y post-Apply: el Plan cubre toda la composición sin atestación de
  conectividad (la VPC aún no existe). El Apply exige la aprobación independiente
  del Terraform Agent. `check "connectivity_review"` es la verificación post-Apply:
  advierte `CONNECTIVITY_PENDING` hasta que Networking atestigua, con evidencia,
  routing, API privada, DNS y alcance a ECR/S3/STS/EKS sobre la VPC creada.
- Transición segura: los módulos reciben valores de variables/locals, no del
  output del gate, y no dependen de él con `depends_on`. Así un cambio de modo o
  de `reviewed_execution` no vuelve desconocidos atributos ForceNew (CIDR, AZ) y
  `NETWORKING_ONLY` → `EKS_CLUSTER` conserva `module.networking[0]` sin
  reemplazos (probado offline). Volver de `EKS_CLUSTER` a `NETWORKING_ONLY`
  destruiría el clúster: el Terraform Agent rechaza planes con borrados fuera de
  la operación Destroy.

## Composición consumible y workspace de un archivo

La raíz de `aws/dev/eks/` expone una composición Terraform. Reutiliza los módulos
hijos mediante rutas relativas y lee `../eks.yaml` y `naming/aws.json` dentro del
mismo paquete Git. No configura provider ni backend en el módulo hijo.

Entradas obligatorias: `team_id`, `application_code`, `environment`, `region`,
`sequence`, `kubernetes_version`, `system_size`, `user_size` y `node_counts`
(objeto System/User con minimum/desired/maximum). El catálogo determina perfiles,
flavors y límites; el consumidor no publica una copia del catálogo.
`proposal_mode` y `reviewed_execution`: ver "Modos de ejecución y Networking".
Ningún modo es una autorización: la ejecución requiere la autorización
independiente del Terraform Agent.

El laboratorio autoriza AWS/dev → main. El caller registra el commit resuelto y
los digests en su journal y revalida la rama antes de publicar. El único archivo
publicado por el contrato `eks-module-v2` es `main.tf`, cuyo source usa `ref=main`.
Cambios de rama después del PR requieren revisión antes de cualquier ejecución;
una rama mutable no ofrece reproducción histórica por sí sola.

La plantilla `aws/dev/main.tf` y `renderPure` se conservan exclusivamente para
compatibilidad del contrato anterior. No son la composición del contrato nuevo.
Las salidas nuevas son `proposed_names`, `resolved_profiles` y `design_status`.
Usar el validador offline oficial, mirror local y lockfile existente; ninguna
validación estática autoriza plan/apply ni demuestra un clúster desplegable.
