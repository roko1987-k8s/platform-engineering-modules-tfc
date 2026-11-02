# Plantillas GitHub Actions — inactivas

Rutas relativas a la raíz del repositorio. Las plantillas se mantienen como
.template en github-actions/validate/, github-actions/apply/ y
github-actions/destroy/, fuera de .github/workflows.
No copiarlas ni activarlas sin una autorización de despliegue independiente.
Su contenido, versión Terraform, SHA de acciones y controles permanecen intactos.

Validate declara eventos pull_request/push, por lo que se ejecutaría automáticamente
si se instalase como workflow. No solicita OIDC ni credenciales AWS; usa init con
backend=false y validate. Los providers y módulos utilizados requieren procedencia
revisada. No ejecutar pruebas genéricas que puedan aprovisionar recursos.

Apply y Destroy son manuales, separan Plan y Execute y requieren main. Plan conserva
las comprobaciones de repositorio/cuenta/habilitación y exit 1 antes de credenciales.
Execute depende del plan, comprueba commit, instancia y checksum y consume el plan
almacenado del mismo run/attempt. Destroy añade una confirmación exacta. No se
retiran estas barreras mientras Networking y contratos operativos estén pendientes.

## Identidad y aislamiento

Las plantillas usan OIDC con roles de variables protegidas; no usan access keys
permanentes. El módulo `aws/dev/iam/modules/github-oidc/` recibe un proveedor existente
y configura roles independientes. No se asume que el repositorio de módulos sea
el repositorio ejecutor. Validate no necesita rol AWS.

El destino actual D001/dev/eks-01 y sus environments, concurrency y keys son
específicos. No constituyen automatización multi-equipo genérica. Antes de adaptar
ese destino se deben revisar juntos rol, cuenta, backend, key, contexto autorizado
y permisos; no cambiar solo etiquetas de instancia. El repositorio ejecutor todavía
contiene un placeholder que debe resolverse mediante revisión antes de activar.

## Controles previos obligatorios

- Verificar proveedor OIDC, sujetos/IDs reales, roles distintos y permisos por fase.
  Backend y aprovisionamiento son ámbitos separados; el módulo IAM no concede
  aprovisionamiento y su acceso al backend requiere opt-in explícito.
- Configurar environments con revisores, prevención de autoaprobación, rama exacta
  y bypass deshabilitado; declararlos en YAML no garantiza esas protecciones.
  Confirmar disponibilidad de esos controles en el plan GitHub utilizado.
- Comprobar vínculo efectivo entre cuenta, rol, backend, instancia, SHA y decisión
  humana. El checksum/commit del artefacto no prueba por sí solo aprobación del plan.
- Revisar la selección amplia approved.*, la integridad de review.txt, permisos
  del artefacto y retención; los planes pueden contener secretos.
- Revisar procedencia de acciones y una versión/lockfile compatibles, sin
  actualizarlos automáticamente. La versión actual declarada sigue siendo 1.10.5.
- Mantener runners sin credenciales heredadas y revisar nuevamente gates antes de
  cualquier ejecución o reintento autorizado. No habilitar pull_request_target.
- No conceder permisos administrativos, de bootstrap S3 ni modificaciones de SG a
  estos roles por defecto. Las reglas 110–502 permanecen intactas.

El bootstrap S3 es independiente en `aws/dev/s3/bootstrap/`, con estado local que
requiere custodia protegida fuera de Git. No usa el bucket que administra para su
propio estado. El rol Destroy de EKS no autoriza destruir ese bucket.
