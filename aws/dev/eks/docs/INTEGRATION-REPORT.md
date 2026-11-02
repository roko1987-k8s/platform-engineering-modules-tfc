> Revisión anterior a la reorganización; las rutas se actualizaron. Para evidencia vigente y movimientos ver REORGANIZATION.md. Los números de línea de esta revisión son históricos.

# Validación final de integración — 2026-11-02

Resultado: interfaces de la composición draft compatibles y validación semántica
local aprobada. Publicable como primera versión de módulos y plantillas INACTIVAS
tras preparar el paquete de publicación; NO es una versión habilitada para AWS.
No se publicó ni se hizo commit. No se modificaron módulos ni catálogo.

## Verificaciones concretas

| Área | Resultado y evidencia |
|---|---|
| Fuente de verdad | `aws/dev/eks.yaml:5–39` conserva Kubernetes 1.36/us-east-1, System S=m7i.large/M=m7i.xlarge, User S=m7i.xlarge/M=m7i.2xlarge, 1–2 por perfil y suma(maximum)<=4. |
| Generador | `aws/dev/eks/tools/render-eks.cjs:16–34` lee el YAML real y valida campos exactos, tamaños, enteros, orden y límites por rol/agregado. No hay entrada developer de EC2, región, backend o identidad. |
| Resolución EC2 | `aws/dev/eks/modules/aws/nodegroups/nodegroups.tf:10–13` usa `var.catalog.nodegroups[each.key].sizes[each.value.size]`, no otro mapa. `variables.tf:38–50` vuelve a validar selección/límites. |
| Configuración derivada | `aws/dev/eks/templates/eks/main.tf.template:31–59` consume catalog.snapshot.json y selección; la instantánea se deriva del YAML y el generador registra digest de origen. No editar snapshots como catálogos independientes. |
| Sources | Ocho llamadas, siete directorios distintos existentes: networking, iam, security-groups, eks, addons (dos instancias), nodegroups y naming. Todos con URL del repo central y `?ref=` del mismo SHA de 40 hex. |
| D001 | Ejemplo exactamente igual al renderer, salvo el marcador SHA. System S 1/1/2 y User M 1/2/2; máximo agregado 4. Nombres resueltos por naming existente, sin copiar módulos. |
| Networking | `main.tf.template:38–50,64–74` mantiene pending/null, módulos AWS count=0 y precondition NETWORKING_PENDING. Generar archivos funciona. La futura publicación de PR no depende de esta precondition; no hay cliente GitHub implementado en este renderer. |
| Automatización | Solo archivos `.yml.template`; no `.github/workflows` activo en el checkout. Apply:30–38 y Destroy:34–42 terminan incondicionalmente antes de AWS. Validate no depende de Networking y no tiene OIDC. |
| S3 | Backend apunta a s3ue1p001dev01; es configuración, no creación de bucket. Bootstrap independiente no se ejecutó. No se consultó existencia/disponibilidad remota del nombre. |

Los valores de versión/región presentes en render-eks.cjs:20 son una comprobación
restrictiva para detectar cambios del catálogo, no un fallback para sustituirlo.
El alcance actual de S/M también se restringe explícitamente y se intersecta con
las claves del catálogo. Ningún mapa EC2 ni límite numérico se duplica en el renderer.
Los valores concretos del ejemplo/pruebas no son defaults de aprovisionamiento.

## Interfaces reales revisadas

La plantilla suministra todos los argumentos obligatorios actuales y no pasa
argumentos inexistentes. Terraform validate confirmó la coherencia estática de
outputs, tipos y cableado con AWS provider 6.20.0.

| Módulo / llamada | Entradas y salidas principales revisadas |
|---|---|
| naming | policy, region, team_id, environment, sequence → names.eks |
| networking | vpc_id, cluster_subnet_ids, node_subnet_ids, conformity, connectivity → vpc_id, cluster_subnet_ids, node_subnet_ids |
| iam | name, tags; pod_identity_roles conserva default vacío → cluster_role_arn, node_role_arns |
| security-groups | name, vpc_id, tags; rules/external_destinations conservan defaults vacíos → security_group_ids |
| eks | name, catalog, kubernetes_version, region, role_arn, subnet_ids, control_plane_security_group_id, kms_key_arn, log_retention_days, tags → name |
| addons / foundation_addons | cluster_name, addons sin CoreDNS, tags; antes de nodegroups |
| nodegroups | cluster_name, kubernetes_version, catalog, subnet_ids, node_role_arns, security_group_ids, selections, root_volumes, tags |
| addons / dns_addon | cluster_name, solo CoreDNS, tags; después de nodegroups |

Se conservaron los SG y sus reglas. Dos llamadas a addons expresan fases de
instalación diferentes, no duplicación del código del módulo. Observability no es
llamado por esta plantilla; su interfaz opcional no se incorporó por iniciativa.

## Correcciones locales y archivos afectados

- `aws/dev/eks/tools/render-eks.cjs:1,13–14`: aclaración de que usa fmt; comprobación
  explícita de string para teamId/moduleSha. Antes regex convertía arrays de un
  elemento a strings y podía aceptar un contexto de tipos inválidos.
- `aws/dev/eks/tests/test-render-eks.cjs`: cinco regresiones nuevas: tipos de contexto,
  límites por rol/agregado derivados del catálogo, mapa EC2 sin fallback y
  equivalencia exacta entre ejemplo y generación. Total actual: 12 casos.
- Nuevo `aws/dev/eks/tests/validate-rendered-eks.cjs`: prueba de integración offline
  con init sin backend, mirror local exclusivo y validate; sin plan/apply.
- Nuevo este reporte y actualización documental de la evidencia en el README de
  la plantilla. No se cambiaron main.tf.template ni el ejemplo para hacer pasar tests.

## Pruebas y alcance real

- 12 pruebas Node del renderer: aprobadas. Los catálogos modificados en pruebas son
  respuestas sintéticas del parser en memoria; el archivo autorizado no se tocó.
- 17 pruebas Python existentes: aprobadas. Incluyen naming puro por console y
  límites estáticos; usan Terraform 1.11.4 ya instalado en un directorio temporal.
- 5 pruebas Python de automatización: aprobadas.
- Terraform fmt -check del árbol terraform: aprobado.
- git diff --check: aprobado.
- Integración generada: Terraform validate, 0 errores y 0 advertencias.

Para esa última prueba se generó un D001 en carpeta temporal y se sustituyeron
SOLO ALLÍ los ocho URLs Git por sus rutas absolutas locales. Se usó un SHA sintético
solo como fixture. No se reescribieron las plantillas ni se descargaron módulos.
Se reutilizó .terraform.lock.hcl existente y proveedor local 6.20.0 en mirror
sin instalación directa de red. init fue -backend=false/-lockfile=readonly; validate
leyó el esquema del proveedor, sin configurarlo contra AWS ni evaluar data lookups.
La carga del proveedor falló dentro del sandbox; la repetición autorizada fuera de
él pasó. El script elimina variables AWS_/TF_ heredadas para las operaciones de
validación y no invoca plan/apply/destroy. No se ejecutaron pruebas HCL de plan mock.

Repetición desde un entorno con Node + yaml disponible:

```sh
NODE_PATH=/ruta/backstage/node_modules \
TERRAFORM_BIN=/ruta/terraform-compatible \
TERRAFORM_PROVIDER_MIRROR=/ruta/mirror-local-proveedores \
node aws/dev/eks/tests/validate-rendered-eks.cjs
```

## Hallazgos pendientes para la primera publicación

1. **Bloqueo de consumo remoto:** módulos/plantillas/tests todavía están sin seguimiento
   y el catálogo modificado localmente. Incluir los archivos revisados, verificar
   exclusión de .terraform, estados, secretos y outputs temporales y autorizar la
   publicación en otra tarea. Después obtener el SHA real que contenga esos paths.
   Para las URLs de los módulos no falta cambiar ningún path: falta ese SHA.
   La descarga Git del commit publicado NO fue probada en esta tarea.
2. **Portabilidad del renderer:** require('yaml') depende hoy de yaml 2.9.1 de
   Backstage mediante NODE_PATH. El checkout central no declara su propio entorno
   Node/dependencias. Antes de anunciar un generador autónomo, acordar y fijar su
   empaquetado; no se introdujo un package manager/arquitectura nuevos. Como borrador
   interno se puede publicar documentando este requisito, sin afirmar autonomía.
3. **Evidencia remota pendiente:** el generador comprueba formato del SHA, no que
   exista ni que coincida con el checkout que suministra catálogo/naming. Revisar
   procedencia en la integración futura. No usar el HEAD histórico sin módulos AWS.
4. **Checkout temporal:** un directorio temporal no es custodia durable. Definir ubicación de
   trabajo/persistencia y revisar todos los borradores antes de su publicación.

Por tanto, SHA es el único valor pendiente dentro de cada source Git, pero NO el
único pendiente para el producto completo. Ninguno de estos puntos exige inventar
redes o activar AWS para publicar una versión explícitamente draft/inactiva.

## Bloqueos para AWS, distintos de publicar módulos inactivos

- Networking sigue pending; faltan opciones exactas y conectividad aprobadas.
- Faltan releases AMI, KMS/volúmenes, retención, versiones/identidad de add-ons y
  compatibilidad regional real. validate no prueba disponibilidad ni permisos.
- El draft no reúne aún todas las preconditions de la composición de referencia
  `aws/dev/eks/examples/composition/main.tf`: aprobación operativa, digest, revisión
  de SG administrado por EKS, add-ons obligatorios y flujos técnicos aprobados.
  No habilitarlo retirando solo Networking. Consolidar esas comprobaciones en una
  tarea autorizada; no se modificaron SG ni contratos para resolverlo incidentalmente.
- Roles/OIDC, Environments sin bypass, backend efectivo por instancia, bootstrap
  S3 y custodia del estado necesitan autorización y verificación. AUDIT.md mantiene
  sus hallazgos abiertos. No se implementaron controles provisionales adicionales.
- El nuevo root remoto necesita lockfile/procedencia y verificación posterior del
  commit publicado. No se ejecuta con el marcador del ejemplo.

No se cambió Backstage, Terraform Agent, contratos ni módulos. No hubo AWS,
creación de bucket/recursos, activación de workflows, commit, push ni PR publicado.
