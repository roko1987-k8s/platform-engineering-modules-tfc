# S3 reutilizable y bootstrap independiente

Rutas relativas a la raíz del repositorio. Implementación local para instalación
nueva, condicionada a confirmar que no existe infraestructura ni estado previo.
No se ha autorizado desplegar, crear buckets ni migrar estados.

```text
aws/dev/s3/
├── modules/s3/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
├── bootstrap/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
└── backend.hcl
```

## Interfaces

El módulo hijo requiere `bucket_name` (string) y `tags` (map(string)), ambos
explícitos y no nulos. Devuelve `bucket` (ID, contrato existente) y `bucket_arn`.
No configura proveedor, backend, región o credenciales. Declara los requisitos
Terraform >=1.10 y <2 y proveedor hashicorp/aws ~>6.0, sin cambiar sus restricciones.
Otros servicios/ambientes reutilizan el mismo módulo y pasan su proveedor, nombre
aprobado y etiquetas; no necesitan copiar recursos ni depender de EKS.

El bootstrap requiere `account_id` de doce dígitos, sin valor por defecto, y
restringe `allowed_account_ids` a esa cuenta. Conserva región us-east-1, nombre
s3ue1p001dev01 y etiquetas teamId=P001/environment=dev. Invoca una sola vez al
módulo y reexpone ambos outputs. No agrega recursos AWS.

## Protecciones y estado

Los seis recursos originales mantienen sus nombres Terraform y dependencias:
bucket, bloqueo público, ownership, versionado, cifrado y política TLS.
Se conservan `force_destroy=false`, `prevent_destroy=true`, los cuatro bloqueos
públicos, BucketOwnerEnforced, Enabled, AES256 y el documento TLS original.
Estas protecciones no se parametrizan para debilitarlas.

El bootstrap utiliza backend local independiente. Su estado y backups requieren
custodia fuera de Git y protección de acceso. `backend.hcl` permanece sin cambios
como configuración parcial del backend remoto de consumidores; no utilizarlo para
inicializar el propio bootstrap. Los outputs del módulo no inicializan backends.

No hay bloques moved: se eligió diseñar para una instalación nueva. Si aparece
infraestructura o estado previo, detenerse. Las seis direcciones antes situadas
en la raíz pasarían a `module.s3.<dirección anterior>`; una adopción o migración
necesita revisión separada antes de cualquier ejecución con credenciales.

## Validación operativa

Desde la raíz del repositorio, ejecutar el validador operativo documentado en
README.md: `tools/terraform/validate-offline.py`. Requiere Terraform compatible,
mirror local y lockfile existente revisado con AWS 6.20.0. Usa copias temporales,
backend=false y lockfile=readonly, sin AWS ni descargas. Pruebas adicionales deben
permanecer fuera del repositorio publicable. No cambiar versiones o lockfiles
para resolver un fallo de validación.

### Resultado de la validación offline S3

Según los resultados comunicados por el responsable, la validación del módulo
S3 y su bootstrap se completó satisfactoriamente con Terraform 1.11.4 instalado
de forma independiente y hashicorp/aws 6.71.0, descargado y autenticado por
HashiCorp durante la preparación del entorno. La ejecución offline utilizó un
mirror local y lockfiles temporales fuera del repositorio.

| Comprobación | Resultado |
|---|---|
| `terraform fmt -check -recursive` | OK |
| `terraform init -backend=false -lockfile=readonly` | OK |
| `terraform validate` | OK |

No se modificaron los archivos originales ni se realizaron conexiones a AWS o
aprovisionamiento. El mirror y los lockfiles temporales no se incorporan al
repositorio. Aún no existe un lockfile definitivo aprobado para el bootstrap o
los workspaces consumidores.

La restricción existente `~> 6.0` admite 6.71.0; no requiere modificar
`versions.tf` ni la configuración del proveedor. Esta validación S3 es distinta
del validador general descrito arriba, que continúa requiriendo un lockfile con
AWS 6.20.0; no se ha actualizado esa herramienta.

El resultado acredita la validación técnica offline con esas versiones. No
verifica credenciales, permisos, existencia o propiedad del bucket, acceso al
backend remoto, aislamiento de estados ni comportamiento en AWS. No equivale a
una aprobación de despliegue. Se conserva el backend local independiente del
bootstrap y el backend remoto separado de los consumidores.

Antes de una instalación real: confirmar ausencia de infraestructura/estado previo,
cuenta y disponibilidad/propiedad del nombre; revisar y fijar un lockfile de
proveedor para el bootstrap, custodio del estado y autorización de despliegue.
Esta implementación local no concede esa autorización.

