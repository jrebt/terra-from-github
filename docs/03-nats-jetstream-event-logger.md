# NATS JetStream + Event Logger (Go)

Tercer microservicio del itinerario K3s. Después de nginx-demo (servir HTML estático) y uptime-kuma (monitoreo con persistencia), este deploy introduce **messaging asíncrono** con NATS JetStream y un microservicio Go que produce y consume eventos.

---

## Conceptos nuevos en este deploy

| Concepto | Qué aprendimos |
|----------|---------------|
| **External Helm chart via ArgoCD** | Desplegar un chart desde un repositorio Helm remoto (no un chart local en el repo Git) |
| **JetStream streams & consumers** | Messaging persistente con acknowledgment, retención y replay |
| **Custom Docker image + CI** | Compilar una app Go, construir imagen Docker y pushear a GHCR automáticamente |
| **Producer/Consumer pattern** | HTTP API que publica eventos y un consumer durable que los almacena |

---

## Arquitectura

```
                         ┌─────────────────────────────────┐
                         │          INTERNET                │
                         └──────────────┬──────────────────┘
                                        │
                              http://events.51.210.89.84.nip.io
                                        │
                         ┌──────────────▼──────────────────┐
                         │     Traefik (Ingress Controller) │
                         │        K3s built-in              │
                         └──────────────┬──────────────────┘
                                        │
                         ┌──────────────▼──────────────────┐
                         │   ClusterIP Service              │
                         │   event-logger:8080               │
                         │   namespace: event-logger         │
                         └──────────────┬──────────────────┘
                                        │
                         ┌──────────────▼──────────────────┐
                         │   Pod: Event Logger (Go)         │
                         │                                  │
                         │   POST /publish  → publica       │
                         │   GET  /events   → últimos 100   │
                         │   GET  /health   → status + NATS │
                         └──────────────┬──────────────────┘
                                        │
                          nats://nats.nats.svc.cluster.local:4222
                                        │
                         ┌──────────────▼──────────────────┐
                         │   NATS Server + JetStream        │
                         │   namespace: nats                 │
                         │                                  │
                         │   Stream: EVENTS                 │
                         │     subjects: events.>            │
                         │     storage: file (PVC 2Gi)       │
                         │     retention: 24h                │
                         │                                  │
                         │   Consumer: event-logger          │
                         │     tipo: durable (push)          │
                         │     ack: explícito                │
                         └──────────────────────────────────┘
```

### Flujo de un evento

```
1. Cliente envía POST /publish con JSON {"name":"deploy","data":"nginx v2"}
                          │
                          ▼
2. Event Logger publica en subject "events.deploy" del stream EVENTS
                          │
                          ▼
3. JetStream persiste el mensaje en disco (PVC 2Gi)
                          │
                          ▼
4. Consumer durable "event-logger" recibe el mensaje (push subscription)
                          │
                          ▼
5. Event Logger almacena en ring buffer in-memory (máx 100 eventos)
                          │
                          ▼
6. msg.Ack() confirma a JetStream que el mensaje fue procesado
                          │
                          ▼
7. Cliente puede consultar GET /events para ver los eventos consumidos
```

---

## Ficheros creados

```
terraform/
├── cluster/apps/
│   ├── argocd-apps/
│   │   └── nats-app.yaml              ← ArgoCD App (Helm chart externo)
│   │   └── event-logger-app.yaml      ← ArgoCD App (chart local)
│   └── event-logger/
│       ├── Chart.yaml                  ← Helm chart metadata
│       ├── values.yaml                 ← Configuración (imagen, ingress, NATS URL)
│       └── templates/
│           ├── deployment.yaml         ← Pod con env NATS_URL, probes en /health
│           ├── service.yaml            ← ClusterIP :8080
│           └── ingress.yaml            ← events.51.210.89.84.nip.io
├── services/event-logger/
│   ├── main.go                         ← HTTP API Go + NATS JetStream
│   ├── go.mod                          ← Módulo Go con nats.go v1.38.0
│   └── Dockerfile                      ← Multi-stage (golang:1.22 → alpine:3.19)
└── .github/workflows/
    └── build-event-logger.yml          ← CI: build + push a GHCR
```

---

## Proceso paso a paso desde cero

### Paso 1 — Desplegar NATS con JetStream

Se creó `cluster/apps/argocd-apps/nats-app.yaml` — un ArgoCD Application con un patrón nuevo respecto a nginx-demo y uptime-kuma.

**Diferencia clave:** En vez de apuntar a un chart local dentro del repo Git (`source.path`), esta Application usa `source.chart` + `source.repoURL` para desplegar directamente desde el repositorio Helm oficial de NATS:

```yaml
source:
  repoURL: https://nats-io.github.io/k8s/helm/charts/   # Helm repo externo
  chart: nats                                              # nombre del chart
  targetRevision: 1.2.4                                    # versión del chart
  helm:
    valuesObject:                                          # valores inline
      config:
        jetstream:
          enabled: true
          fileStore:
            enabled: true
            dir: /data
            pvc:
              enabled: true
              size: 2Gi
```

Esto le dice a ArgoCD: "descarga el chart `nats` v1.2.4 de ese Helm repo y aplícalo con estos valores". No necesitamos copiar el chart a nuestro repo.

### Paso 2 — Escribir el microservicio Go

Se creó `services/event-logger/main.go` con tres endpoints HTTP y lógica de NATS JetStream:

**Conexión a NATS con retry:**
```go
nc, err = nats.Connect(natsURL,
    nats.MaxReconnects(-1),           // reconectar indefinidamente
    nats.ReconnectWait(2*time.Second), // esperar 2s entre reintentos
)
```

**Creación del stream:**
```go
js.AddStream(&nats.StreamConfig{
    Name:     "EVENTS",
    Subjects: []string{"events.>"},   // wildcard: events.deploy, events.test, etc.
    Storage:  nats.FileStorage,        // persistido en disco (PVC)
    MaxAge:   24 * time.Hour,          // retención de 24 horas
})
```

**Consumer durable con goroutine:**
```go
go func() {
    js.Subscribe("events.>", func(msg *nats.Msg) {
        // deserializar, guardar en ring buffer, hacer ACK
        msg.Ack()
    }, nats.Durable("event-logger"), nats.DeliverAll())
}()
```

### Paso 3 — Crear el Dockerfile y CI

**Multi-stage build** — compila con Go 1.22 y ejecuta sobre Alpine 3.19:
```dockerfile
FROM golang:1.22-alpine AS builder
COPY go.mod ./
COPY *.go ./
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o event-logger .

FROM alpine:3.19
COPY --from=builder /app/event-logger .
ENTRYPOINT ["./event-logger"]
```

`CGO_ENABLED=0` produce un binario estático sin dependencias de C — perfecto para Alpine.

**GitHub Actions** (`.github/workflows/build-event-logger.yml`):
- Se dispara automáticamente con push a `services/event-logger/**`
- Hace login en GHCR con `GITHUB_TOKEN`
- Pushea la imagen con tags `latest` y el SHA del commit

**Paso manual obligatorio post-build:** Hacer el paquete GHCR público en GitHub → Profile → Packages → event-logger → Package settings → Change visibility → Public. Sin esto, K3s no puede hacer pull de la imagen.

### Paso 4 — Crear el Helm chart y ArgoCD Application

Se creó el chart local `cluster/apps/event-logger/` siguiendo el mismo patrón que uptime-kuma, con estas diferencias:

| Aspecto | uptime-kuma | event-logger |
|---------|-------------|--------------|
| Imagen | Docker Hub (`louislam/uptime-kuma`) | GHCR (`ghcr.io/jrebt/event-logger`) |
| pullPolicy | `IfNotPresent` | `Always` (tag `latest`) |
| Variables de entorno | ninguna | `NATS_URL`, `PORT` |
| Health probes | path: `/` | path: `/health` |

La ArgoCD Application (`event-logger-app.yaml`) usa el mismo patrón que nginx-demo y uptime-kuma: auto-sync, prune, selfHeal, CreateNamespace.

### Paso 5 — Commits y push

Se realizaron 3 commits separados para mantener cambios atómicos y facilitar rollbacks:

```
e35e30b  Add NATS JetStream via external Helm chart with ArgoCD        (1 fichero)
b48c10d  Add Event Logger Go microservice with NATS JetStream and CI   (4 ficheros)
e5e134e  Add Event Logger Helm chart and ArgoCD application            (6 ficheros)
ea82673  Fix Event Logger Docker build by using go mod tidy            (hotfix)
```

El hotfix fue necesario porque sin `go.sum` en el repo (Go no estaba instalado localmente), `go mod download` no podía verificar checksums. La solución: usar `go mod tidy` en el Dockerfile que genera `go.sum` durante el build.

---

## Cómo probarlo manualmente

### 1. Verificar health

```bash
curl http://events.51.210.89.84.nip.io/health
```

Respuesta esperada:
```json
{"nats_connected":true,"status":"ok"}
```

Si `nats_connected` es `false`, NATS no está listo o el pod de event-logger arrancó antes que NATS (se reconectará automáticamente).

### 2. Publicar un evento

```bash
curl -X POST http://events.51.210.89.84.nip.io/publish \
  -H "Content-Type: application/json" \
  -d '{"name":"deploy","data":"nginx actualizado a v2"}'
```

Respuesta esperada:
```json
{"status":"published","subject":"events.deploy"}
```

El campo `name` determina el subject NATS: `name: "deploy"` → subject: `events.deploy`.

### 3. Consultar eventos consumidos

```bash
curl http://events.51.210.89.84.nip.io/events
```

Respuesta esperada:
```json
[
  {
    "name": "deploy",
    "data": "nginx actualizado a v2",
    "subject": "events.deploy",
    "timestamp": "2026-02-13T08:19:35Z"
  }
]
```

### 4. Publicar varios eventos y verificar

```bash
# Publicar múltiples eventos con diferentes subjects
curl -s -X POST http://events.51.210.89.84.nip.io/publish \
  -H "Content-Type: application/json" \
  -d '{"name":"alert","data":"CPU al 90%"}'

curl -s -X POST http://events.51.210.89.84.nip.io/publish \
  -H "Content-Type: application/json" \
  -d '{"name":"user.login","data":"admin desde 192.168.1.1"}'

curl -s -X POST http://events.51.210.89.84.nip.io/publish \
  -H "Content-Type: application/json" \
  -d '{"name":"deploy","data":"uptime-kuma v1.23"}'

# Ver todos los eventos
curl -s http://events.51.210.89.84.nip.io/events | python3 -m json.tool
```

### 5. Probar NATS directamente (desde nats-box)

Si tienes acceso SSH al nodo master:

```bash
# Ver info del servidor NATS
kubectl exec -n nats deployment/nats-box -- nats server info --server nats://nats:4222

# Ver el stream EVENTS
kubectl exec -n nats deployment/nats-box -- nats stream info EVENTS --server nats://nats:4222

# Ver el consumer
kubectl exec -n nats deployment/nats-box -- nats consumer info EVENTS event-logger --server nats://nats:4222

# Publicar un evento directamente desde NATS (bypass HTTP)
kubectl exec -n nats deployment/nats-box -- \
  nats pub events.manual '{"name":"manual","data":"desde nats-box"}' --server nats://nats:4222
```

---

## Resumen

### ¿Para qué ha servido todo esto?

Este deploy ha sido un ejercicio progresivo de complejidad en el cluster K3s:

| Deploy | Qué aprendimos |
|--------|----------------|
| **nginx-demo** | Helm chart local básico, Service NodePort, ArgoCD GitOps, deploy-apps workflow |
| **uptime-kuma** | PVC (persistencia), Ingress con Traefik + nip.io, ClusterIP Service |
| **NATS + Event Logger** | Helm chart externo via ArgoCD, custom Docker image con CI/CD a GHCR, messaging asíncrono con JetStream, producer/consumer pattern en Go |

### Capacidades demostradas

1. **ArgoCD gestiona dos tipos de sources**: charts locales en el repo Git (nginx, uptime-kuma, event-logger) y charts remotos de Helm repos externos (NATS)
2. **CI/CD completo para microservicios custom**: push código → GitHub Actions build → imagen en GHCR → ArgoCD detecta y despliega
3. **Comunicación entre microservicios**: Event Logger se conecta a NATS via DNS interno de Kubernetes (`nats.nats.svc.cluster.local`)
4. **Persistencia de mensajes**: JetStream almacena eventos en disco (PVC) con retención configurable, sobreviven a reinicios de pods
5. **Resiliencia**: reconexión automática a NATS, consumers durables que no pierden mensajes, health probes para que Kubernetes reinicie pods fallidos

### Estado actual del cluster

```
┌─────────────────────────────────────────────────────────┐
│                    K3s Cluster (OVH b2-7)                │
│                                                         │
│  namespace: nginx-demo     → nginx (HTML estático)       │
│  namespace: uptime-kuma    → monitoreo (PVC 2Gi)         │
│  namespace: nats           → NATS JetStream (PVC 2Gi)    │
│  namespace: event-logger   → Go API (producer/consumer)  │
│  namespace: argocd         → GitOps controller            │
│  namespace: kube-system    → Traefik, CoreDNS, metrics   │
│                                                         │
│  URLs:                                                  │
│    http://uptime.51.210.89.84.nip.io   → Uptime Kuma     │
│    http://events.51.210.89.84.nip.io   → Event Logger    │
└─────────────────────────────────────────────────────────┘
```
