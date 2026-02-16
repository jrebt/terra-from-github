# Estrategia Multi-Cloud: Terraform + Ansible

## Objetivo

Repositorio de infraestructura multi-cloud que permita:
- Desplegar en un proveedor cloud hoy y expandir a otros en el futuro
- Sincronizacion diaria para mantener todos los clouds activos al dia
- Añadir y eliminar recursos de forma controlada en todos los proveedores

## Diagrama General

```
                         ┌─────────────────┐
                         │   Git Repo      │
                         │  (monorepo)     │
                         └────────┬────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
     ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
     │  Cloud A (OVH) │  │  Cloud B (AWS) │  │  Cloud C (GCP) │
     │  activo hoy    │  │  en 2 meses    │  │  si se necesita│
     └────────┬───────┘  └────────┬───────┘  └────────┬───────┘
              │                   │                   │
              └───────────────────┼───────────────────┘
                                  ▼
                    Modulos Terraform compartidos
                    (compute, network, security, dns)
                    Cada modulo tiene implementacion
                    por proveedor
```

## Estructura del Repositorio

```
infra-multicloud/
│
├── modules/                          # Modulos Terraform reutilizables
│   ├── compute/                      # Abstraccion: "quiero una VM"
│   │   ├── ovh/                      # Implementacion OVH (OpenStack)
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── aws/                      # Implementacion AWS (EC2)
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── gcp/                      # Implementacion GCP (Compute Engine)
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   ├── network/                      # VPC / Security Groups
│   │   ├── ovh/
│   │   ├── aws/
│   │   └── gcp/
│   ├── kubernetes/                   # Cluster K8s
│   │   ├── ovh/                      # K3D / K3s
│   │   ├── aws/                      # EKS
│   │   └── gcp/                      # GKE
│   └── dns/                          # DNS records
│       ├── ovh/
│       ├── aws/
│       └── gcp/
│
├── environments/                     # Configuracion por entorno
│   ├── dev/
│   │   ├── ovh/                      # Cloud A - activo
│   │   │   ├── main.tf              # Usa modules/*/ovh
│   │   │   ├── variables.tf
│   │   │   ├── terraform.tfvars
│   │   │   ├── backend.tf           # State en GCS/S3
│   │   │   └── outputs.tf           # Genera inventario Ansible
│   │   ├── aws/                      # Cloud B - futuro
│   │   │   ├── main.tf              # Usa modules/*/aws
│   │   │   ├── variables.tf
│   │   │   ├── terraform.tfvars
│   │   │   ├── backend.tf
│   │   │   └── outputs.tf
│   │   └── gcp/                      # Cloud C - si se necesita
│   │       └── ...
│   ├── staging/
│   │   ├── ovh/
│   │   ├── aws/
│   │   └── gcp/
│   └── prod/
│       ├── ovh/
│       ├── aws/
│       └── gcp/
│
├── ansible/                          # Configuracion (cloud-agnostic)
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── dev/
│   │   │   ├── ovh.yml              # Generado por Terraform output
│   │   │   ├── aws.yml
│   │   │   └── gcp.yml
│   │   ├── staging/
│   │   └── prod/
│   ├── playbooks/
│   │   ├── setup-base.yml           # Comun a todos los clouds
│   │   ├── setup-k8s.yml
│   │   └── setup-monitoring.yml
│   └── roles/
│       ├── common/                   # Paquetes base, users, ssh
│       ├── docker/
│       ├── kubernetes/
│       └── monitoring/
│
├── .github/workflows/
│   ├── sync-daily.yml               # Sincronizacion diaria
│   ├── plan-on-pr.yml               # Plan en PRs
│   ├── apply-on-merge.yml           # Apply al mergear
│   └── destroy.yml                  # Destroy manual
│
├── scripts/
│   ├── sync-all-clouds.sh           # Orquesta plan/apply en todos los clouds activos
│   └── generate-inventory.sh        # Genera inventarios Ansible desde Terraform
│
└── config.yaml                       # Define que clouds estan activos
```

## Archivo config.yaml (controla que clouds estan activos)

```yaml
environments:
  dev:
    clouds:
      ovh:
        enabled: true
        region: GRA11
      aws:
        enabled: false          # Habilitar cuando este listo
        region: eu-west-1
      gcp:
        enabled: false
        region: europe-west1
  prod:
    clouds:
      ovh:
        enabled: true
      aws:
        enabled: false
      gcp:
        enabled: false
```

## Modulos Compartidos (ejemplo)

Los modulos abstraen las diferencias entre proveedores. El mismo concepto ("quiero una VM") tiene implementaciones distintas por cloud pero con la misma interfaz de variables y outputs.

```hcl
# modules/compute/ovh/main.tf
resource "openstack_compute_instance_v2" "vm" {
  name        = var.name
  flavor_name = var.flavor
  image_name  = var.image
  key_pair    = var.keypair
  network { name = "Ext-Net" }
}

# modules/compute/aws/main.tf
resource "aws_instance" "vm" {
  ami           = var.image
  instance_type = var.flavor
  key_name      = var.keypair
  tags = { Name = var.name }
}

# environments/dev/ovh/main.tf (usa el modulo OVH)
module "master" {
  source  = "../../../modules/compute/ovh"
  name    = "k3d-master"
  flavor  = "b2-7"
  image   = "Ubuntu 22.04"
  keypair = var.ssh_keypair
}

# environments/dev/aws/main.tf (usa el modulo AWS)
module "master" {
  source  = "../../../modules/compute/aws"
  name    = "k3d-master"
  flavor  = "t3.medium"      # Equivalente a b2-7
  image   = "ami-xxxxx"      # Ubuntu 22.04
  keypair = var.ssh_keypair
}
```

## Sincronizacion Diaria

### Workflow

```yaml
# .github/workflows/sync-daily.yml
name: Daily Infrastructure Sync
on:
  schedule:
    - cron: "0 6 * * 1-5"    # L-V a las 06:00 UTC
  workflow_dispatch:           # Manual

jobs:
  detect-clouds:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.clouds.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - id: clouds
        run: |
          # Lee config.yaml y genera matrix de clouds activos
          # Output: {"include":[{"cloud":"ovh","env":"dev"},...]}

  sync:
    needs: detect-clouds
    strategy:
      matrix: ${{ fromJson(needs.detect-clouds.outputs.matrix) }}
      fail-fast: false         # Un cloud falla, los otros siguen
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Terraform Init
        working-directory: environments/${{ matrix.env }}/${{ matrix.cloud }}
        run: terraform init

      - name: Terraform Plan
        working-directory: environments/${{ matrix.env }}/${{ matrix.cloud }}
        run: terraform plan -out=tfplan -detailed-exitcode
        # Exit code 2 = hay cambios

      - name: Terraform Apply (si hay cambios)
        if: steps.plan.outputs.exitcode == 2
        working-directory: environments/${{ matrix.env }}/${{ matrix.cloud }}
        run: terraform apply tfplan

      - name: Generate Ansible Inventory
        run: |
          cd environments/${{ matrix.env }}/${{ matrix.cloud }}
          terraform output -json > ../../../ansible/inventory/${{ matrix.env }}/${{ matrix.cloud }}.json

      - name: Run Ansible
        if: steps.plan.outputs.exitcode == 2
        run: |
          ansible-playbook ansible/playbooks/setup-base.yml \
            -i ansible/inventory/${{ matrix.env }}/${{ matrix.cloud }}.yml
```

### Como funciona la sincronizacion (añadir recursos)

```
Dia 1: Creas infra en OVH (3 VMs + 1 cluster K8s)
  └── commit + push → apply en OVH ✓
  └── State OVH: [vm1, vm2, vm3, k8s]

Dia 3: Añades un balanceador de carga
  └── commit + push → apply en OVH ✓
  └── State OVH: [vm1, vm2, vm3, k8s, lb]
  └── sync diario → OVH ya esta al dia, no hace nada (plan sin cambios)

Mes 3: Habilitas AWS en config.yaml (enabled: true)
  └── sync diario detecta AWS enabled
  └── terraform plan en AWS → crea toda la infra desde 0
      (3 VMs + 1 cluster K8s + 1 lb — lo mismo que OVH tiene)
  └── AWS queda al dia con lo que tiene OVH

Dia siguiente: Cambias algo (por ejemplo, añades un nuevo servicio)
  └── commit + push
  └── sync diario → aplica en OVH ✓ y en AWS ✓ (ambos al dia)
```

### Como funciona la sincronizacion (eliminar recursos)

La eliminacion sigue exactamente el mismo flujo que la creacion. Terraform compara el **state actual** (lo que existe en el cloud) con el **codigo** (lo que esta definido en los .tf) y aplica las diferencias.

```
Dia 1: Infra actual en OVH y AWS
  State: [vm1, vm2, vm3, k8s, lb, redis, monitoring]

Dia 10: Decides eliminar redis y monitoring del codigo
  └── Borras o comentas los bloques de redis y monitoring en main.tf
  └── commit + push
  └── terraform plan detecta:
      ~ Plan: 0 to add, 0 to change, 2 to destroy
      - redis (will be destroyed)
      - monitoring (will be destroyed)
  └── apply → elimina redis y monitoring de OVH ✓
  └── State OVH: [vm1, vm2, vm3, k8s, lb]

Sync diario (06:00 UTC del dia siguiente):
  └── terraform plan en AWS detecta lo mismo:
      ~ Plan: 0 to add, 0 to change, 2 to destroy
      - redis (will be destroyed)
      - monitoring (will be destroyed)
  └── apply → elimina redis y monitoring de AWS ✓
  └── State AWS: [vm1, vm2, vm3, k8s, lb]
  └── Ambos clouds quedan sincronizados
```

**Importante:** El sync diario del workflow puede aplicar automaticamente (`terraform apply`) o solo generar el plan y notificar para aprobacion manual. La recomendacion por entorno:

| Entorno | Sync automatico | Motivo |
|---------|----------------|--------|
| dev | Si (auto-apply) | Bajo riesgo, velocidad |
| staging | Plan + notificacion | Revision antes de aplicar |
| prod | Plan + aprobacion manual | Maximo control, evitar eliminaciones accidentales |

### Proteccion contra eliminaciones accidentales

Para recursos criticos, Terraform permite protegerlos con `lifecycle`:

```hcl
resource "aws_instance" "database" {
  # ...

  lifecycle {
    prevent_destroy = true    # Terraform rechaza el destroy
  }
}
```

Tambien se puede usar una politica de aprobacion en el workflow:

```
Sync detecta destroy → Envia notificacion (Slack/Email)
                      → Requiere aprobacion manual
                      → Solo entonces ejecuta apply
```

### Escenario completo (timeline)

```
┌──────────┬──────────────────────────────────┬──────────────┬──────────────┐
│ Dia      │ Accion                           │ OVH          │ AWS          │
├──────────┼──────────────────────────────────┼──────────────┼──────────────┤
│ Dia 1    │ Crear infra inicial              │ 3 VMs, K8s   │ (disabled)   │
│ Dia 3    │ Añadir load balancer             │ + LB         │ (disabled)   │
│ Dia 5    │ Añadir Redis                     │ + Redis      │ (disabled)   │
│ Dia 10   │ Eliminar Redis del codigo        │ - Redis      │ (disabled)   │
│ Dia 15   │ Añadir monitoring                │ + Monitoring │ (disabled)   │
│ Mes 3    │ Habilitar AWS (config.yaml)      │ sin cambios  │ Crea TODO    │
│          │                                  │              │ (3VM,K8s,LB, │
│          │                                  │              │  Monitoring) │
│ Mes 3+1d │ Añadir nueva VM                  │ + VM4        │ (sync diario)│
│ Mes 3+2d │ Sync diario                      │ sin cambios  │ + VM4        │
│ Mes 4    │ Eliminar LB del codigo           │ - LB         │ (sync diario)│
│ Mes 4+1d │ Sync diario                      │ sin cambios  │ - LB         │
└──────────┴──────────────────────────────────┴──────────────┴──────────────┘
```

## State Management

Cada combinacion environment+cloud tiene su propio state de Terraform, nunca compartido:

```
backend "gcs" {                        # o "s3" para AWS
  bucket = "mi-terraform-state"
  prefix = "dev/ovh"                   # dev/ovh, dev/aws, prod/ovh, etc.
}
```

| Environment | Cloud | State path |
|-------------|-------|------------|
| dev | ovh | `dev/ovh/terraform.tfstate` |
| dev | aws | `dev/aws/terraform.tfstate` |
| dev | gcp | `dev/gcp/terraform.tfstate` |
| prod | ovh | `prod/ovh/terraform.tfstate` |
| prod | aws | `prod/aws/terraform.tfstate` |

## Decisiones de Arquitectura

| Decision | Recomendacion |
|----------|---------------|
| Repositorio | Monorepo (un solo repo para toda la infra) |
| Modulos | Un modulo por concepto (compute, network...) con implementacion por cloud |
| Environments | Directorio por entorno (dev/staging/prod) y por cloud dentro |
| State | Un state separado por environment+cloud (nunca compartir state entre clouds) |
| Sync | Workflow diario con matrix strategy (paraleliza clouds activos) |
| Activacion | config.yaml controla que clouds estan habilitados |
| Ansible | Roles cloud-agnostic, inventarios generados por Terraform |
| Eliminacion | Mismo flujo que creacion: borrar del codigo → plan detecta destroy → apply |
| Proteccion | lifecycle.prevent_destroy para recursos criticos, aprobacion manual en prod |
