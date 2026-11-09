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


## Networking: VPC y subnets creadas por Terraform

El módulo `modules/aws/networking` crea la VPC y las subnets privadas; no
administra Security Groups (los de EKS pertenecen al módulo `security-groups`). En la composición, la entrada única es
`reviewed_execution.networking` (se mantiene dentro de `reviewed_execution` porque
el Terraform Agent verifica el conjunto exacto de variables de esta raíz):

```hcl
networking = {
  vpc_cidr             = "<asignado por Networking>"
  cluster_subnet_cidrs = ["<asignado>", "<asignado>"]
  node_subnet_cidrs    = ["<asignado>", "<asignado>"]
  approval_reference   = "<ticket de aprobación>"
  connectivity         = null # se atestigua cuando la VPC ya existe
}
```

- Región: `var.region`, validada contra `aws/dev/eks.yaml`. El provider heredado
  y todas las AZ deben pertenecer a ella. Las subnets se reparten de forma
  determinista en al menos dos AZ (nombres ordenados, subnet `i` → zona `i mod n`).
- Nombres: `module.naming` genera `names.vpc` y `subnet_names`
  (`<names.vpc>-cluster-NN`, `<names.vpc>-node-NN`). Los tags `Team`,
  `ApplicationCode` y `Environment` salen de las entradas autorizadas y
  prevalecen sobre los tags revisados.
- Gate en dos etapas, sin dependencia circular: con los CIDR aprobados y la
  referencia de aprobación se crean la VPC y las subnets. IAM, security groups,
  EKS, add-ons y node groups esperan a que `connectivity` esté atestiguada
  (`check "connectivity_review"` avisa con `CONNECTIVITY_PENDING`).
  Las salidas `proposed_subnet_names` y `networking_status` reflejan ese estado.
- `proposal_mode` sigue aceptando solo `DESIGN_WITHOUT_AWS_ACCOUNT`, así que los
  módulos AWS siguen con cero instancias y `NETWORKING_PENDING` bloquea el plan.
- No se crean IGW, NAT Gateway ni VPC endpoints: la salida hacia ECR, S3, STS y
  EKS es una decisión arquitectónica pendiente (ver
  `modules/aws/networking/README.md`). No se incorporan CIDR ficticios.

## Composición consumible y workspace de un archivo

La raíz de `aws/dev/eks/` expone una composición Terraform. Reutiliza los módulos
hijos mediante rutas relativas y lee `../eks.yaml` y `naming/aws.json` dentro del
mismo paquete Git. No configura provider ni backend en el módulo hijo.

Entradas obligatorias: `team_id`, `application_code`, `environment`, `region`,
`sequence`, `kubernetes_version`, `system_size`, `user_size` y `node_counts`
(objeto System/User con minimum/desired/maximum). El catálogo determina perfiles,
flavors y límites; el consumidor no publica una copia del catálogo.
`proposal_mode` acepta únicamente `DESIGN_WITHOUT_AWS_ACCOUNT` en esta fase.
`reviewed_execution` es una interfaz tipada futura, null por defecto: incluso si
se suministra, el modo de diseño mantiene los módulos AWS sin instancias y el
gate bloquea ejecución. No es una autorización de infraestructura.

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
