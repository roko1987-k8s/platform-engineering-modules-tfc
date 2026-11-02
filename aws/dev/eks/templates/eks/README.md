# Plantilla reutilizable EKS — borrador local

El catálogo autorizado continúa exclusivamente en `aws/dev/eks.yaml`. No se
modificaron sus opciones: Kubernetes 1.36, us-east-1, System S/M, User S/M,
ON_DEMAND, 1–2 nodos por perfil y suma de máximos <=4. Networking sigue pending.
Este trabajo no confirma disponibilidad regional de Kubernetes/EC2/AMI.

`main.tf.template` reutiliza la composición del borrador D001 histórico, ahora archivado fuera del repositorio, sin cambiar
los módulos. Conserva naming, networking, IAM, SG, EKS, add-ons y nodegroups;
las referencias locales se sustituyen por sources Git SHA inmutables. El módulo
security-groups se referencia sin cambiarlo ni añadir reglas 110–502.

## Generación offline

Requisitos: Node y paquete `yaml` ya usado en Backstage, y Terraform para `fmt`
únicamente. No se añadieron dependencias a módulos ni se instalaron herramientas.
Desde Backstage puede usarse `NODE_PATH="$PWD/node_modules"` para ejecutar el
script del checkout central sin instalar otro paquete. Antes de portar el renderer
a otro ejecutor, declarar y fijar esa dependencia en su empaquetado existente.
No es todavía una API del Terraform Agent ni un nuevo contrato de Backstage.

La función `render(context, selection)` del script devuelve archivos en memoria.
Su CLI recibe tres argumentos: contexto JSON autorizado, selección JSON y raíz
de salida. Invoca solo `terraform fmt -`; no init, plan, apply, red ni GitHub.
La CLI rechaza sobrescribir carpetas existentes.

```sh
node aws/dev/eks/tools/render-eks.cjs contexto-autorizado.json seleccion.json /ruta/de/salida
```

El contexto contiene teamId, environment, sequence y moduleSha. El llamador futuro
resuelve estos valores de la solicitud autorizada; NO son opciones del developer.
El generador comprueba forma de SHA, no existencia ni publicación/procedencia del
commit. Debe ejecutarse desde un checkout confiable del catálogo/naming y registrar
su SHA/digest real antes de conectar la integración. No usar el HEAD histórico que
carece de módulos AWS. El contexto de ejemplo tiene un marcador y falla a propósito.

La selección permite exactamente system/user con size S/M y minimum/desired/maximum
enteros ordenados dentro del catálogo. Se prueban las cuatro combinaciones S/M y
se rechazan cantidades fuera de rango o campos extra de región, instancia o identidad.
No hay un mapa alternativo de tipos EC2 en el generador. El módulo nodegroups
resuelve S/M desde el catálogo. Las opciones adicionales requerirán autorización
explícita del catálogo antes de agregarlas a la plantilla.

Se generan cinco archivos en `workspaces/D001/terraform/aws/dev/eks-01/` (o D002
según contexto autorizado):

- `main.tf`: composición, sin definiciones de recursos AWS ni módulos copiados.
- `backend.hcl`: bucket central exacto y key `states/D001/aws/dev/eks-01/terraform.tfstate`.
- `catalog.snapshot.json`: instantánea derivada del YAML, sin editarla a mano.
- `naming.snapshot.json`: política de naming central, sin lógica duplicada.
- `generation.json`: selección/contexto, SHA solicitado y digests de las fuentes.

Las instantáneas son entradas de configuración para un commit de workspace
reproducible, no copias de módulos ni un catálogo alternativo editable. No contienen
secretos. La verificación de procedencia/digests debe completarse antes de ejecutar.

## Ejemplo D001 System S / User M

Ver `D001-System-S-User-M.main.tf.example`, ilustrativo e inactivo: ningún SHA
publicado que contenga los módulos se inventó. Selección propuesta:

| Perfil | Tamaño | EC2 del catálogo | minimum | desired | maximum |
|---|---|---|---|---|---|
| System | S | m7i.large | 1 | 1 | 2 |
| User | M | m7i.2xlarge | 1 | 2 | 2 |

La cantidad elegida es ilustrativa dentro de los límites, no una aprobación de
aprovisionamiento. Los nombres son `eksue1d001dev01`, `vpcue1d001dev01`,
`infraue1d001dev01`, `userue1d001dev01`, resueltos por el módulo naming existente.
No se crea una VPC por presentar su nombre propuesto.

`main.tf` incluye backend S3 parcial; no inicializar hasta autorización. El draft
mantiene networking null/pending y un precondition NETWORKING_PENDING, con módulos
AWS a count=0. Esa barrera no garantiza que init o la inicialización del proveedor
no consulten red: ejecutar únicamente comprobaciones offline durante esta etapa.
El renderer rehúsa un catálogo con Networking ya aprobado; la transición a ejecución
requiere una revisión específica, no retirar un booleano como único paso.

Faltan entradas revisadas de releases AMI, volúmenes/KMS, retención, add-ons,
segmentos/conectividad y aprobaciones operativas. La composición draft reutilizada
NO reemplaza todas las validaciones de la composición de referencia
`aws/dev/eks/examples/composition`; antes de habilitarla hay que consolidar sus
precondiciones de compatibilidad, procedencia, add-ons y flujos autorizados. No se
modificó ahora la arquitectura ni se habilitó ningún flujo de seguridad.

## Pruebas ejecutables sin AWS

```sh
node aws/dev/eks/tests/test-render-eks.cjs
TERRAFORM_BIN=/ruta/al/terraform-compatible python3 -m unittest discover -s aws/dev/eks/tests -p 'test_*.py' -v
python3 -m unittest discover -s aws/dev/eks/automation/terraform-aws/tests -v
terraform fmt -check -recursive terraform
```

Se reutilizó el binario 1.11.4 ya presente en un directorio temporal para las pruebas de naming
que usan init local sin proveedores y console. No se actualizó la instalación 1.5.7.
El generador comprueba HCL mediante fmt. No se hizo init Git de los sources remotos
ni validate semántico del workspace generado: falta el SHA publicado y el lockfile.
Los mocks HCL existentes se conservaron, pero no se ejecutaron en esta tarea;
no hubo ningún terraform plan, ni siquiera contra mocks.

## Evidencia final de integración

La revisión posterior está en `aws/dev/eks/docs/INTEGRATION-REPORT.md`.
Amplía la evidencia anterior: 12 casos del renderer aprobados y validación semántica
del D001 aprobada (0 errores/advertencias) con sources locales solo en una copia
temporal, mirror existente y backend deshabilitado. No valida todavía el transporte
Git por SHA publicado. Ver `aws/dev/eks/tests/validate-rendered-eks.cjs` para repetirla.
