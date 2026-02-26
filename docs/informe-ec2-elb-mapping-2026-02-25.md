# Informe de Infraestructura AWS EC2 - Load Balancer Mapping

**Fecha:** 25 de febrero de 2026
**Región:** eu-central-1
**Cuenta:** 694245763875

---

## 1. Resumen Ejecutivo

| Métrica | Valor |
|---|---|
| Total instancias EC2 | 41 |
| Instancias detrás de ELB | 12 (29%) |
| Instancias sin ELB | 29 (71%) |
| Targets healthy | 8 |
| Targets unhealthy | 4 |
| Targets unused | 2 |

---

## 2. Instancias detrás de Elastic Load Balancer

| Nombre | Instance ID | IP Privada | Target Group(s) | Estado |
|---|---|---|---|---|
| ahoramanagment-pro | i-0d28b14c4525d8330 | 172.31.2.139 | ahoramanagement-pro | HEALTHY |
| api-publicaciones | i-0a7ecc1d1aeca3ea7 | 172.31.23.28 | api-publicaciones | HEALTHY |
| pre-docker01-Cajamar-Plat | i-0dac004a591f13520 | 172.31.25.230 | hecate-cajamar-pre, hestia-cajamar-pre, musubi-cajamar-pre, tamias-cajamar-pre, temis-cajamar-pre | HEALTHY |
| pro-docker01-Cajamar-Plat | i-03e3677e1f5cfe245 | 172.31.32.171 | hecate-cajamar-pro, musubi-cajamar-pro, tamias-cajamar-pro, hestia-cajamar-pro, reverso-cajamar-pro, temis-cajamar-pro | DEGRADED |
| hecate_pascual | i-090165a645b1e96d2 | 172.31.26.185 | hecate-pascual-pro, parser-pascual-pro | HEALTHY |
| pre-armarios-plat | i-0c576c7be380a5106 | 172.31.31.191 | mqtt-keybuu-pro, pypi-keybuu-pro | HEALTHY |
| pre-docker01-Odoo-plat | i-03a5cc6871062e15c | 172.31.28.211 | odoo-pre | UNHEALTHY |
| pro-odoo-wv | i-08ee7035a2ee4ae2c | 172.31.46.202 | odoo-pro | UNHEALTHY |
| pro-docker-01 | i-0ce5d93e69b780386 | 172.31.32.68 | metabase-ahoramanagement-pro | UNUSED |
| metabase-pro-01 | i-03264c6d21cc9df8f | 172.31.35.5 | reportes-ahoramanagement-pro | HEALTHY |
| new-framework-dev | i-05b0cd89b170c0727 | 172.31.22.146 | sandbox-ahoramanagement | HEALTHY |
| sandbox-cimenta2 | i-0a483e6b5dd736de9 | 172.31.18.209 | test01 | UNUSED |

---

## 3. Instancias sin Elastic Load Balancer

| Nombre | Instance ID | IP Privada | Tipo |
|---|---|---|---|
| pro-corp-web-server | i-022694c3dcca13dd0 | 172.31.18.207 | Producción |
| pro-ecs-cronjobs | i-08030346474493375 | 172.31.27.134 | Producción |
| pro-web-server | i-0afb962efc751edf5 | 172.31.35.187 | Producción |
| pre-web-server | i-022eea36be53b753a | 172.31.32.180 | Pre-producción |
| ec2-micro-rem -sftp haya | i-03116d40ae2b7c1fe | 172.31.36.178 | Utilidad |
| pre2-web-server | i-0fb4c72e448ee5a6f | 172.31.46.218 | Pre-producción |
| pro-sareb-web-server | i-07c4c9f7c6995579d | 172.31.41.122 | Producción |
| pro-altamira-bastion | i-03e3ea9dd02641869 | 172.31.48.100 | Bastión |
| pro-securitas-bastion | i-0c296e3bc3fcb9c7c | 172.31.60.61 | Bastión |
| pro-garsa-bastion | i-0fac61464d70b6727 | 172.31.40.235 | Bastión |
| pro-securitas-network-check | i-05ff623a82d250844 | 172.31.61.231 | Monitorización |
| pro-ionic-server | i-08f5c87f444e04e0c | 172.31.40.3 | Producción |
| pro-laravel-01 | i-0e92972e5e4dab5a9 | 172.31.16.104 | Producción |
| pro-reverso-aam-wv-interno | i-08dc59d9c87c20d39 | 172.31.48.129 | Producción |
| prod-sistema-i2 | i-0a321a085dfa2c21a | 172.31.25.210 | Producción |
| pre-aa-wv-dofix | i-04d3fac67f7745db0 | 172.31.48.7 | Pre-producción |
| ahoramanagment-test | i-02f1ec40fce8e735c | 172.31.3.229 | Testing |
| pro-aa-wv-dofix | i-02800725f0aa82af0 | 172.31.48.5 | Producción |
| ihookit | i-07759e8df3ff8ec21 | 172.31.17.130 | Producción |
| migracion-cajamar | i-0604d9cae0d97a859 | 172.31.17.236 | Migración |
| pre-test-cimenta2-cajamar | i-0b3887c3906e7d2cf | 172.31.24.198 | Pre-producción |
| VPN-CAJAMAR 80-PRO | i-0c4acedc95593869e | 172.16.108.80 | VPN |
| VPN-CAJAMAR 82-DEV | i-0a0ba5b590b526e2d | 172.16.108.82 | VPN |
| VPN CAJAMAR 81-PRE | i-0ea82e9584f4e2c85 | 172.16.108.81 | VPN |
| mv-alberto-pruebas | i-09365000c7e16b343 | 172.31.28.253 | Testing |
| pro-cimenta2-cajamar | i-0aac1eb9d0a1c2e7e | 172.31.22.127 | Producción |
| new-cimenta2-php8-cajamar | i-06ee373d8e6c86cfb | 172.31.18.89 | Producción |
| metabase-pro | i-00557d6daec170017 | 172.31.30.131 | Producción |
| prod-sistemas-i2-new | i-0089f122dfae8ad89 | 172.31.30.227 | Producción |
| wv-jenkins-pro | i-02b204a09f1ad6b38 | 172.31.44.95 | CI/CD |

---

## 4. Incidencias Detectadas

### CRÍTICO

| Instancia | Problema | Target Groups Afectados |
|---|---|---|
| pro-docker01-Cajamar-Plat (i-03e3677e1f5cfe245) | 2 targets unhealthy en producción | hecate-cajamar-pro, temis-cajamar-pro |
| pro-odoo-wv (i-08ee7035a2ee4ae2c) | Target unhealthy en producción | odoo-pro |

### MEDIO

| Instancia | Problema | Target Groups Afectados |
|---|---|---|
| pre-docker01-Odoo-plat (i-03a5cc6871062e15c) | Target unhealthy en pre-producción | odoo-pre |

### BAJO

| Instancia | Problema | Target Groups Afectados |
|---|---|---|
| pro-docker-01 (i-0ce5d93e69b780386) | Target registrado pero unused | metabase-ahoramanagement-pro |
| sandbox-cimenta2 (i-0a483e6b5dd736de9) | Target registrado pero unused | test01 |

---

## 5. Estado SSM (Systems Manager)

| Estado SSM | Cantidad |
|---|---|
| Online | 33 |
| ConnectionLost | 1 (pro-securitas-bastion) |

---

## 6. Recomendaciones

1. **Investigar inmediatamente** los health checks fallidos en producción (pro-docker01-Cajamar-Plat y pro-odoo-wv)
2. **Revisar conectividad SSM** del bastión pro-securitas-bastion (i-0c296e3bc3fcb9c7c) - SSM Agent sin reportar desde el 14/02/2026
3. **Evaluar targets unused** - determinar si deben eliminarse de los target groups o reactivarse
4. **Revisar instancias de producción sin ELB** - valorar si requieren balanceo de carga para alta disponibilidad
