# Preparación de primera publicación DRAFT — 2026-11-02

Checkout permanente: `.`. Permisos del directorio: 0700.
El traslado no sobrescribió archivos y ya no existe el checkout en su antigua ruta.
Rama local: main. Remoto fetch/push: https://github.com/roko1987-k8s/platform-engineering-vars-tfc.git.
Main remoto se consultó y se actualizó origin/main mediante fetch; base verificada:
`1b45cd178e04cecc1e7eca10032c84f9ea93b5f9`.

La rama previa catalog/aws-eks-dev se conserva. Su commit 49fa1b3 ya estaba integrado
en main remoto mediante PR #1. Se avanzó main local solo por fast-forward.
Antes del cambio de rama se respaldó el catálogo público y se restauraron sus bytes
aprobados; no hubo stash, rebase ni creación de commits. Frente a main remoto solo
cambian comentarios/formato del catálogo; las opciones son semánticamente iguales.

## Inventario propuesto

101 archivos exactos en publication-files.txt. Alcance exclusivo:
`.gitignore`, `aws/dev/eks.yaml`, `aws/dev/eks/`.
Distribución: `{'root-ignore': 1, 'catalog': 1, '.gitignore': 1, 'README.md': 1, 'automation': 11, 'docs': 6, 'examples': 13, 'modules': 42, 'naming': 1, 'templates': 5, 'tests': 18, 'tools': 1}`.

Incluye catálogo, los 42 archivos de módulos, naming, plantillas/generador,
automatización inactiva, pruebas/fixtures, lockfiles y documentación.
Los dos catálogos de fixtures son sintéticos, no fuentes autorizadas alternativas.
aws/dev/kubernetes.yaml es un borrador previo fuera de alcance, permanece sin
seguimiento y no figura en este inventario. Azure permanece intacto.
No se usará git add . ni git add -A.

No hay workspaces D001/D002, .terraform, estados, planes, logs, caches, node_modules,
.env ni temporales en la lista. Los lockfiles de proveedores sí se incluyen.
Se añadió .gitignore raíz para proteger también credenciales locales y archivos
accidentales fuera del paquete. Se verificó check-ignore sobre rutas de prueba sin
crear esos archivos. No se leyeron .env ni almacenes de credenciales.
Escaneo de patrones de access keys, tokens GitHub y claves privadas: sin hallazgos;
es una comprobación heurística, no una garantía absoluta de ausencia de secretos.

## Integridad y referencias

Catálogo idéntico a la huella aprobada:
`bd96ec38c9cee68e608a21cb75427c6f1fc2b26deac099fcb7bb1f23bc6fd760`.
Los 42 archivos de módulos y la política naming coinciden con el manifiesto previo.
Todos los sources Git centrales usan //aws/dev/eks/modules/; los ejemplos/contexto
conservan <SHA_REAL>. La plantilla usa el token interno @@MODULE_SHA@@.
No se publicó ni inventó el SHA del futuro commit.

## Pruebas repetidas desde el checkout permanente

- 12 pruebas del generador: PASS.
- 17 pruebas de naming y estructura: PASS.
- 5 pruebas de automatización: PASS.
- terraform fmt -check: PASS.
- validate D001, D002, composición y bootstrap: 0 errores, 0 advertencias.
- YAML Validate/Apply/Destroy: PASS.
- diff --check, whitespace explícito y exclusiones: PASS.

Integración usó Terraform 1.11.4 existente, provider 6.20.0 de mirror local,
lockfile readonly y backend=false en copias temporales, sin fuentes Git descargadas.
No se ejecutó plan/apply/destroy ni tests HCL de plan mock. La lectura de esquemas
del proveedor se ejecutó fuera del sandbox con autorización. No se configuró AWS.
Las salidas D001/D002 quedaron fuera del checkout central, bajo temporales de test.

Networking continúa pending. Los workflows solo son .yml.template y conservan
exit 1 antes de AWS. S3 y EKS no se crearon. No hubo cambios en SG, contratos,
Backstage, Orchestrator ni Terraform Agent. No se actualizaron herramientas.
El generador autónomo sigue pendiente de empaquetar yaml; hoy lo reutiliza de
Backstage mediante NODE_PATH, documentado como requisito de esta versión draft.
Los documentos de auditorías previas conservan evidencia histórica de un directorio temporal;
la ubicación vigente y el resultado de publicación son los de este documento.

## Comandos propuestos, NO ejecutados

Solo después de autorización explícita y nueva comprobación del remoto:

```sh
cd "$(git rev-parse --show-toplevel)"
git fetch origin main
git merge --ff-only origin/main
git add -- .gitignore aws/dev/eks.yaml aws/dev/eks/
git diff --cached --check
git diff --cached --stat
git commit -m "feat(aws/eks): add reusable EKS catalog modules and draft automation"
git push origin main:main
```

Si main remoto cambia, el merge no es fast-forward, hay conflictos o cambia el
contenido revisado, detenerse y revisar; no forzar push. main protegido puede
requerir PR: no eludir protecciones. El inventario debe coincidir con el staged
diff antes del commit. La publicación no autoriza bootstrap ni activar workflows.
Actualmente el índice está vacío: no se ejecutó git add, commit o push.
