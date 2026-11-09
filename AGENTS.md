# Reglas del repositorio

- No incluir rutas absolutas personales, nombres de usuario locales ni rutas temporales de una máquina en archivos versionados, documentación, ejemplos, pruebas, logs o manifiestos generados. Revisar también las salidas de herramientas antes de copiarlas.
- Documentar rutas relativas a la raíz del repositorio e indicar esa base. Para archivos externos, usar variables portables explícitas sin valores personales.
- Calcular rutas de scripts desde su propia ubicación o desde la raíz Git; usar las APIs de directorios temporales del lenguaje y respetar la configuración del entorno. No fijar directorios temporales de un sistema operativo.
- Antes de entregar cambios, revisar todos los archivos versionados y los nuevos archivos propuestos en busca de rutas personales o temporales y secretos; ejecutar las pruebas locales seguras afectadas y `git diff --check`. Actualizar las referencias de la documentación operativa cuando cambien rutas, sin agregar inventarios de laboratorio o reportes internos al árbol publicable.
- Conservar URLs Git e identificadores legítimos. No modificar nombres de recursos AWS, módulos Terraform, convenciones de naming, Security Groups, catálogo EKS ni contratos como parte de una limpieza de privacidad.
- Una limpieza de archivos actuales no autoriza reescribir historial, ejecutar operaciones AWS, hacer commit, push ni force push.

## Separación arquitectónica obligatoria

- Cada servicio AWS mantiene sus módulos independientes por servicio. Los módulos bajo `aws/dev/eks/modules/` son exclusivamente componentes y utilidades de la composición EKS; no alojar allí workflows, automatizaciones ni scripts de bootstrap S3.
- Mantener `aws/dev/eks.yaml` como catálogo y `aws/dev/main.tf` como plantilla principal EKS. Esta última requiere renderizado; no tratar sus tokens como HCL ejecutable ni duplicar la plantilla.
- Mantener S3 bajo `aws/dev/s3/`, con el código solicitado en `modules/s3/`. El módulo hijo no configura provider ni backend: ambos pertenecen a `aws/dev/s3/bootstrap/`, con backend local independiente del bucket administrado. Conservar los seis recursos, las protecciones y los nombres Terraform; parametrizar únicamente nombre de bucket y etiquetas. La implementación actual está autorizada solo localmente para instalación nueva, condicionada a confirmar ausencia de infraestructura/estado previo. No añadir bloques moved ni migrar estados sin nueva revisión.
- Separar IAM de GitHub Actions en `aws/dev/iam/modules/github-oidc/` del IAM EKS en `aws/dev/eks/modules/aws/iam/`. Reutilizar las fuentes existentes sin duplicar políticas. No inferir roles, attachments o proveedores OIDC a partir de plantillas: acordar primero la interfaz y propiedad de recursos, sin ampliar permisos.
- Mantener plantillas Actions en `github-actions/validate/`, `github-actions/apply/` y `github-actions/destroy/`, inactivas como `.template` y fuera de `.github/workflows`. Mantener sus barreras operativas.
- Verificar dependencias antes de mover archivos; actualizar consumidores, documentación, pruebas e inventarios. Reportar incompatibilidades en lugar de eliminar funcionalidad. No crear directorios vacíos ni archivos de relleno para representar propuestas.

- Mantener el repositorio central mínimo y reutilizable: módulos, catálogo/plantilla, herramientas operativas y documentación de uso. Mantener herramientas compartidas en `tools/terraform/`, documentación operativa en los README y workflows separados en `github-actions/`. No publicar laboratorios, reportes internos, inventarios de reorganización, fixtures ni ejemplos redundantes. Las pruebas temporales y sus resultados se ejecutan fuera del repositorio, mediante APIs de temporales y variables portables.
- Antes de extraer recursos a módulos, identificar entradas, salidas, dependencias, propietario del proveedor/backend y cambios de direcciones de estado. Si se requieren decisiones nuevas sobre estado, permisos o recursos, detener esa conversión y documentar opciones en la documentación operativa correspondiente; no asumir estado vacío ni efectuar migraciones implícitas.

- Para validación operativa, usar `tools/terraform/validate-offline.py` con herramientas ya instaladas, mirror local y lockfile existente revisado. Trabajar en copias temporales fuera del repositorio, con backend=false y lockfile=readonly, sin AWS ni descargas. Mantener fixtures y pruebas mock fuera del árbol publicable y no convertirlas en operaciones reales.

- El módulo IAM/OIDC solo recibe un proveedor GitHub existente por ARN obligatorio y nunca lo administra. Exigir entradas explícitas de repositorio ejecutor/IDs y roles plan/apply/destroy con confianza exacta aud/sub/repositorio/ref/environment; no inferir que el repositorio de módulos ejecuta workflows ni crear rol Validate.
- Mantener los documentos IAM originales como fuentes reutilizadas sin alterarlos. El backend se habilita por opt-in de fases para un único estado; no ampliar sus acciones ni usar comodines. Mantener aprovisionamiento bloqueado hasta tener políticas revisadas; no aceptar permisos arbitrarios o administrativos como defaults. Los datos sintéticos pertenecen solo a ensayos offline externos al repositorio, nunca a configuración de despliegue.

## Limpieza y versiones

- Conservar módulos Terraform independientes y sus archivos de versiones propios, sin fusionar main.tf. Preservar también terraform.tf donde ya declare versiones, sin duplicarlo ni normalizarlo durante una limpieza.
- No modificar required_version, required_providers o lockfiles existentes durante una limpieza. No actualizar automáticamente Terraform/providers, unificar restricciones, crear versions.yaml, Makefile o mecanismos de sincronización. Reportar diferencias para una revisión posterior.
- Antes de retirar un archivo, verificar que no sea dependencia del Agent, renderer, módulo, validación operativa o Actions. Si su retirada puede romper generación, detener esa eliminación y reportarla. Conservar las fuentes de documentos que los módulos leen aunque sus nombres parezcan ejemplos.
- La limpieza no autoriza cambios de recursos, variables, outputs, contratos, políticas S3, permisos IAM o Security Groups. Mantener Networking pendiente y Actions inactivo. No publicar rutas personales, secretos, estados, planes, credenciales o respaldos internos.

## Nombres genéricos y reutilización de componentes compartidos

1. Todos los nombres de archivos, módulos, plantillas y componentes compartidos deben ser genéricos y reutilizables.
2. No incorporar identificadores específicos de equipos (D001, D002, P001), ambientes (dev, qa, prod), instancias (eks-01), usuarios o ramas en los nombres de archivos ni de componentes reutilizables.
3. Recibir los valores específicos mediante variables, parámetros o configuración. Los valores sujetos a identidad o autorización deben proceder del contexto autorizado y conservar las validaciones actuales; parametrizar no permite eludir controles ni introducir valores fuera de los catálogos aprobados.
4. Cada equipo podrá utilizar sus propios workspaces y ramas consumiendo los módulos centrales, sin duplicarlos. Mantener separados el código compartido y la configuración específica de cada workspace.
5. No incluir rutas locales personales, nombres de usuario locales, credenciales ni secretos en archivos publicados o generados para publicación. Usar rutas relativas al repositorio o variables portables y revisar los archivos propuestos antes de publicar. Nunca mostrar valores sensibles al informar hallazgos.
6. Mantener las excepciones estructurales existentes y autorizadas, como carpetas por proveedor cloud, ambientes y bootstrap central. La regla de nombres genéricos no obliga a eliminar esas carpetas, a renombrar workspaces de equipos ni a cambiar nombres de recursos sujetos a la nomenclatura aprobada.
7. Estas normas complementan las instrucciones actuales de cada proyecto sin reemplazarlas ni ampliar autorizaciones. Los destinos específicos documentados como ejemplos o evidencia histórica no constituyen convenciones para nombrar componentes reutilizables. No renombrar archivos existentes, cambiar contratos, mover carpetas ni migrar implementaciones como efecto incidental de añadir estas reglas; cualquier cambio de ese alcance requiere una tarea autorizada.
