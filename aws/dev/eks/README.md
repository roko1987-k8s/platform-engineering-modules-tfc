# Plantillas reutilizables EKS DEV — inactivas

Checkout permanente: `.`.
Inventario y preparación de publicación: `docs/PUBLICATION.md`.

Catálogo autorizado: `../eks.yaml`, sin cambios. Kubernetes 1.36, us-east-1,
System S/M, User S/M, 1–2 nodos por perfil y suma de máximos <=4. Networking sigue
pending; no se verificó disponibilidad regional real ni se provisionó AWS.

Ver `docs/STRUCTURE.md` para el árbol y movimientos; `docs/REORGANIZATION.md` para
pruebas y huellas de esta reorganización. `docs/INTEGRATION-REPORT.md` conserva
la revisión anterior con rutas actualizadas; sus números de línea son históricos.

## Componentes y propiedad

`modules/naming` implementa naming; `naming/aws.json` contiene su política.
`modules/aws/networking` valida segmentos existentes; IAM, SG, EKS, nodegroups y
add-ons mantienen sus responsabilidades. Observability sigue siendo opcional.
No cambió ningún archivo de modules/ ni la política de naming en esta reorganización.

La composición genérica está en `examples/composition/`; está deshabilitada por
defecto y conserva sus aprobaciones y precondiciones. El generador draft está en
`tools/render-eks.cjs`; la plantilla remota en `templates/eks/`. No hay workspaces
reales ni módulos copiados para equipos dentro de este repositorio.

La automatización se encuentra en `automation/terraform-aws/`. Ningún workflow se
instala en .github/workflows. Bootstrap S3 es independiente y no se ejecuta para
validar el root EKS. Cierre del bucket requiere inventario, custodia, autorización
explícita y destrucción independiente al terminar el laboratorio.

## Validación local desde la raíz del repositorio

Node requiere el paquete yaml ya disponible en Backstage; definir NODE_PATH hacia
sus node_modules mientras se acuerda el empaquetado autónomo del renderer. Usar
TERRAFORM_BIN para un binario compatible ya instalado, sin actualizar herramientas.

```sh
node aws/dev/eks/tests/test-render-eks.cjs
python3 -m unittest discover -s aws/dev/eks/tests -p 'test_*.py' -v
python3 -m unittest discover -s aws/dev/eks/automation/terraform-aws/tests -v
terraform fmt -check -recursive aws/dev/eks
node aws/dev/eks/tests/validate-rendered-eks.cjs
```

El último comando requiere TERRAFORM_BIN y TERRAFORM_PROVIDER_MIRROR locales.
Genera D001/D002 fuera del repo central, sustituye sources solo en copias temporales
y ejecuta fmt, init con backend=false/lockfile=readonly y validate. No ejecuta
plan/apply/destroy, no descarga fuentes Git y no configura credenciales AWS.
Los tests HCL existentes son mocks de plan, pero no se ejecutan con estos comandos.

## Límites antes de AWS

Los SG y reglas 110–502 no se modificaron. Los flujos técnicos y el SG administrado
por AWS requieren revisión; no se habilitaron reglas por omisión. Faltan red real,
conectividad aprobada, releases AMI, KMS/volúmenes, add-ons, permisos/OIDC efectivos,
backend autorizado y aprobaciones. La composición draft debe consolidar las gates
de la referencia antes de habilitarla. No basta con cambiar Networking a approved.
Ver automation/terraform-aws/AUDIT.md para hallazgos abiertos.
