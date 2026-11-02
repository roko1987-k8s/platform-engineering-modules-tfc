# Estructura definitiva aprobada

Todas las rutas siguientes son relativas a platform-engineering-vars-tfc.
El catálogo único permanece en `aws/dev/eks.yaml`; su código de aprovisionamiento
está separado bajo `aws/dev/eks/`.

```text
aws/dev/
├── eks.yaml
└── eks/
    ├── README.md
    ├── .gitignore
    ├── modules/
    │   ├── naming/
    │   └── aws/
    │       ├── networking/
    │       ├── iam/
    │       ├── security-groups/
    │       ├── eks/
    │       ├── nodegroups/
    │       ├── addons/
    │       └── observability/
    ├── naming/aws.json
    ├── templates/eks/
    ├── tools/render-eks.cjs
    ├── examples/composition/
    ├── automation/terraform-aws/
    │   ├── bootstrap/
    │   ├── iam/
    │   ├── templates/
    │   └── tests/
    ├── tests/
    │   └── fixtures/
    └── docs/
```

## Mapa aplicado

| Ruta anterior | Ruta actual |
|---|---|
| terraform/modules/ | aws/dev/eks/modules/ |
| terraform/naming/ | aws/dev/eks/naming/ |
| terraform/templates/ | aws/dev/eks/templates/ |
| terraform/tools/ | aws/dev/eks/tools/ |
| terraform/tests/ | aws/dev/eks/tests/ |
| terraform/examples/aws/eks-dev/ | aws/dev/eks/examples/composition/ |
| automation/terraform-aws/ | aws/dev/eks/automation/terraform-aws/ |
| terraform/README.md y .gitignore | aws/dev/eks/README.md y .gitignore |
| STRUCTURE.md, INTEGRATION-REPORT.md | aws/dev/eks/docs/ |

El antiguo `terraform/examples/workspaces/` se archivó fuera del checkout, sin
eliminar su contenido. La cobertura estática usa el ejemplo .tf.example de la
plantilla. La prueba mock de Networking se conserva como receta
`tests/fixtures/workspace-draft.tftest.hcl.template` y se materializa únicamente
junto a un root temporal; no se ejecutó plan en esta reorganización.

Los únicos workspaces D001/D002 se generan para platform-engineering-devs:
`workspaces/<teamId>/terraform/aws/dev/eks-01/`. No hay directorio workspaces en
el repositorio central. Las instantáneas de catálogo/naming existen solo en las
salidas generadas, no como nuevos catálogos fuente centrales.

Los sources Git usan exclusivamente el prefijo
`//aws/dev/eks/modules/` y un SHA inmutable. El ejemplo y contexto mantienen
`<SHA_REAL>` hasta publicar un commit que contenga las nuevas rutas. La plantilla
interna usa @@MODULE_SHA@@, sustituido por el renderer tras validar su formato.
No hay compatibilidad automática con las rutas Git anteriores.

## Integración posterior

Backstage conserva selección S/M y contratos actuales. En una tarea futura, el
Terraform Agent resolverá contexto autorizado y SHA verificable, generará el root
con estas plantillas y publicará el PR del workspace. Este renderer no implementa
identidad ni publicación de PR. Networking pendiente permite generación/revisión,
pero bloquea ejecución; completar red no basta para habilitar el resto de los gates.

Plan, aprobación independiente de Apply y autorización separada de Destroy siguen
preparados como workflows inactivos. OIDC, mínimo privilegio, Environments sin
bypass, procedencia y backend efectivo deben revisarse antes de AWS. Vault sigue
siendo diseño futuro; el bucket s3ue1p001dev01 tiene bootstrap y cierre independientes.
La copia histórica de automatización en Backstage no se modificó en esta tarea;
la fuente central para la siguiente revisión es esta nueva ubicación.
