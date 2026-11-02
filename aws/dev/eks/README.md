# Composición EKS para Terraform Agent — bloqueada

Rutas de este documento relativas a la raíz del repositorio. Catálogo autorizado:
`aws/dev/eks.yaml`. Plantilla principal: `aws/dev/main.tf`. Ocho módulos permanecen
en `aws/dev/eks/modules/`: networking, IAM, security-groups, EKS, nodegroups,
add-ons, observability y naming. Sus fuentes Git y contratos no se modifican.

## Contrato de generación

`aws/dev/eks/tools/render-eks.cjs` exporta render(context, selection) y una CLI:

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
en el entorno del llamador; TERRAFORM_BIN selecciona el binario existente para fmt.

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
de la raíz. Los ensayos y fixtures se ejecutan fuera del repositorio publicable.
