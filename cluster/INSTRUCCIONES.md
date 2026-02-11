# Instrucciones - Cluster K3s (1 Master + 1 Worker)

## Prerrequisitos

Los siguientes secrets deben estar configurados en GitHub (Settings > Secrets and variables > Actions):

| Secret | Descripcion |
|--------|-------------|
| `OVH_ENDPOINT` | Endpoint API OVH (ej: `ovh-eu`) |
| `OVH_APPLICATION_KEY` | Application Key de OVH |
| `OVH_APPLICATION_SECRET` | Application Secret de OVH |
| `OVH_CONSUMER_KEY` | Consumer Key de OVH |
| `OVH_SERVICE_NAME` | Project ID de OVH Public Cloud |
| `OPENSTACK_TENANT_ID` | Tenant ID de OpenStack |
| `OPENSTACK_USERNAME` | Usuario de OpenStack |
| `OPENSTACK_PASSWORD` | Password de OpenStack |
| `OVH_SSH_PUBLIC_KEY` | Clave publica SSH |
| `OVH_SSH_PRIVATE_KEY` | Clave privada SSH |

Si ya usas el proyecto original en `ovh/terra-from-github-main/`, estos secrets ya estan configurados.

## Estructura del cluster

- **1 Master** (`k3s-new-master-1`): Nodo de control con K3s server + ArgoCD
- **1 Worker** (`k3s-new-worker-1`): Nodo de trabajo con K3s agent
- **Flavor**: `b2-7` (2 vCPU, 7GB RAM) para ambos nodos
- **Region**: GRA11
- **OS**: Ubuntu 22.04

## Pasos para desplegar

### 1. Subir ficheros al repositorio

```bash
cd /home/jrebaza/terraform
git add cluster/
git commit -m "Add k3s-new cluster config (1 master + 1 worker)"
git push origin main
```

### 2. Ejecutar el workflow

1. Ir a GitHub > Actions > **OVH K3s New Cluster Deploy**
2. Click en **Run workflow**
3. Seleccionar `plan` para ver los cambios propuestos
4. Si el plan es correcto, ejecutar de nuevo con `apply`

### 3. Verificar el cluster

Una vez completado el workflow, conectar al master por SSH:

```bash
ssh ubuntu@<IP_MASTER>
```

Verificar los nodos:

```bash
kubectl get nodes
```

Resultado esperado:

```
NAME                STATUS   ROLES                  AGE   VERSION
k3s-new-master-1    Ready    control-plane,master   Xm    v1.28.5+k3s1
k3s-new-worker-1    Ready    worker                 Xm    v1.28.5+k3s1
```

### 4. Acceder a ArgoCD

La informacion de acceso se muestra en los logs del workflow de Ansible. Tambien se puede obtener por SSH:

```bash
# Obtener el NodePort de ArgoCD
kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}'

# Obtener la password de admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Acceder en el navegador: `https://<IP_MASTER>:<NODEPORT>`
- Usuario: `admin`
- Password: (la obtenida con el comando anterior)

## Destruir la infraestructura

1. Ir a GitHub > Actions > **OVH K3s New Cluster Deploy**
2. Click en **Run workflow**
3. Seleccionar `destroy`

Esto eliminara todas las VMs y el keypair de OVH.

## Diferencias con el proyecto original

| Aspecto | Original (`ovh/terra-from-github-main/`) | Nuevo (`cluster/`) |
|---------|------------------------------------------|---------------------|
| Nombre cluster | `k3s-prod` | `k3s-new` |
| Workers | 0 (deshabilitados) | 1 (habilitado) |
| Inventario Ansible | Solo masters | Masters + Workers |
| Playbook k3s-install | Workers comentados | Workers activos |
| Playbook cluster-config | Label workers comentado | Label workers activo |
