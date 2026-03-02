#!/bin/bash
# ============================================================================
# EC2 Cost Optimization Report - Frankfurt (eu-central-1)
# Analiza CPU de los ultimos 30 dias, recomienda right-sizing agresivo,
# genera archivo de reporte y plan de Reserved Instances.
# Uso: bash ec2-cost-optimizer.sh
# Salida: ec2-cost-report-YYYY-MM-DD.txt
# ============================================================================

REGION="eu-central-1"
DAYS=30
END_DATE=$(date -u +%Y-%m-%dT00:00:00Z)
START_DATE=$(date -u -d "${DAYS} days ago" +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u -v-${DAYS}d +%Y-%m-%dT00:00:00Z)
REPORT_FILE="ec2-cost-report-$(date +%Y-%m-%d).txt"

# Limpiar cache de precios anterior (puede tener datos corruptos)
rm -f /tmp/ec2price_* 2>/dev/null

# ---- Funcion awk para calculos ----
calc() {
  awk "BEGIN {printf \"%.2f\", $1}"
}

# Funcion para escribir a pantalla y archivo
out() {
  echo "$1"
  echo "$1" >> "$REPORT_FILE"
}

# Limpiar archivo previo
> "$REPORT_FILE"

out "============================================================================"
out "  EC2 COST OPTIMIZATION REPORT"
out "  Region: ${REGION} (Frankfurt)"
out "  Periodo analizado: ultimos ${DAYS} dias"
out "  Generado: $(date '+%Y-%m-%d %H:%M:%S')"
out "============================================================================"
out ""

# ---- Obtener instancias running ----
echo "Obteniendo instancias EC2..."
INSTANCES=$(aws ec2 describe-instances \
  --region "${REGION}" \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,Name:Tags[?Key==`Name`].Value|[0]}' \
  --output json 2>/dev/null)

if [ -z "$INSTANCES" ] || [ "$INSTANCES" = "[]" ]; then
  out "No se encontraron instancias running en ${REGION}"
  exit 1
fi

TOTAL_INSTANCES=$(echo "$INSTANCES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
out "Total instancias running: ${TOTAL_INSTANCES}"
out ""

# ---- Recopilar tipos unicos y obtener precios + specs via python3 ----
echo "Obteniendo precios y specs de todos los tipos de instancia..."

# Extraer tipos unicos
UNIQUE_TYPES=$(echo "$INSTANCES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in sorted(set(i['Type'] for i in data)):
    print(t)
")

# Obtener specs (vCPUs, RAM) de todos los tipos de una sola llamada
ALL_TYPES_LIST=$(echo "$UNIQUE_TYPES" | tr '\n' ' ')
SPECS_JSON=$(aws ec2 describe-instance-types \
  --region "${REGION}" \
  --instance-types $ALL_TYPES_LIST \
  --query 'InstanceTypes[].{Type:InstanceType,vCPUs:VCpuInfo.DefaultVCpus,RAM:MemoryInfo.SizeInMiB}' \
  --output json 2>/dev/null)

# Obtener precios de cada tipo via Pricing API y construir JSON completo
# Esto lo hacemos todo en python3 para evitar problemas de parsing en bash
echo "Consultando AWS Pricing API para cada tipo..."

PRICING_JSON=$(python3 << 'PYEOF'
import subprocess, json, sys

def get_price(itype):
    """Obtener precio On-Demand desde AWS Pricing API"""
    try:
        result = subprocess.run([
            'aws', 'pricing', 'get-products',
            '--region', 'us-east-1',
            '--service-code', 'AmazonEC2',
            '--filters',
            f'Type=TERM_MATCH,Field=instanceType,Value={itype}',
            'Type=TERM_MATCH,Field=location,Value=EU (Frankfurt)',
            'Type=TERM_MATCH,Field=operatingSystem,Value=Linux',
            'Type=TERM_MATCH,Field=tenancy,Value=Shared',
            'Type=TERM_MATCH,Field=preInstalledSw,Value=NA',
            'Type=TERM_MATCH,Field=capacitystatus,Value=Used',
            '--query', 'PriceList[0]',
            '--output', 'text'
        ], capture_output=True, text=True, timeout=30)
        data = json.loads(result.stdout.strip())
        terms = data['terms']['OnDemand']
        for k in terms:
            for sk in terms[k]['priceDimensions']:
                price = float(terms[k]['priceDimensions'][sk]['pricePerUnit']['USD'])
                if price > 0:
                    return price
    except:
        pass
    return 0.0

# Leer tipos desde stdin (uno por linea)
import os
types_str = os.environ.get('INSTANCE_TYPES', '')
types = types_str.strip().split()

prices = {}
for t in types:
    print(f"  Precio de {t}...", file=sys.stderr)
    prices[t] = get_price(t)

print(json.dumps(prices))
PYEOF
)

# Si fallo python3, intentar con variable de entorno
if [ -z "$PRICING_JSON" ] || [ "$PRICING_JSON" = "{}" ]; then
  PRICING_JSON=$(INSTANCE_TYPES="$ALL_TYPES_LIST" python3 << 'PYEOF'
import subprocess, json, sys, os

def get_price(itype):
    try:
        result = subprocess.run([
            'aws', 'pricing', 'get-products',
            '--region', 'us-east-1',
            '--service-code', 'AmazonEC2',
            '--filters',
            f'Type=TERM_MATCH,Field=instanceType,Value={itype}',
            'Type=TERM_MATCH,Field=location,Value=EU (Frankfurt)',
            'Type=TERM_MATCH,Field=operatingSystem,Value=Linux',
            'Type=TERM_MATCH,Field=tenancy,Value=Shared',
            'Type=TERM_MATCH,Field=preInstalledSw,Value=NA',
            'Type=TERM_MATCH,Field=capacitystatus,Value=Used',
            '--query', 'PriceList[0]',
            '--output', 'text'
        ], capture_output=True, text=True, timeout=30)
        data = json.loads(result.stdout.strip())
        terms = data['terms']['OnDemand']
        for k in terms:
            for sk in terms[k]['priceDimensions']:
                price = float(terms[k]['priceDimensions'][sk]['pricePerUnit']['USD'])
                if price > 0:
                    return price
    except:
        pass
    return 0.0

types = os.environ['INSTANCE_TYPES'].strip().split()
prices = {}
for t in types:
    print(f"  Precio de {t}...", file=sys.stderr)
    prices[t] = get_price(t)
print(json.dumps(prices))
PYEOF
  )
fi

echo ""

# ============================================================================
# ANALISIS PRINCIPAL EN PYTHON3
# Todo el procesamiento pesado se hace en python3 para evitar bugs de bash
# ============================================================================

REPORT_BODY=$(INSTANCES_JSON="$INSTANCES" SPECS_JSON="$SPECS_JSON" PRICING_JSON="$PRICING_JSON" REGION="$REGION" START_DATE="$START_DATE" END_DATE="$END_DATE" python3 << 'PYEOF'
import subprocess, json, sys, os

# ---- Cargar datos ----
instances = json.loads(os.environ['INSTANCES_JSON'])
specs_list = json.loads(os.environ['SPECS_JSON'])
prices = json.loads(os.environ['PRICING_JSON'])
region = os.environ['REGION']
start_date = os.environ['START_DATE']
end_date = os.environ['END_DATE']

# Indexar specs por tipo
specs = {}
for s in specs_list:
    specs[s['Type']] = {'vCPUs': s['vCPUs'], 'RAM': s['RAM']}

# ---- Tabla de tamanos ordenada (para multi-step downgrade) ----
SIZE_ORDER = ['nano', 'micro', 'small', 'medium', 'large', 'xlarge', '2xlarge',
              '4xlarge', '8xlarge', '9xlarge', '12xlarge', '16xlarge', '24xlarge', 'metal']

# Familias equivalentes mas baratas (para cross-family migration)
CHEAPER_FAMILY = {
    't2': 't3a', 't3': 't3a',
    'm4': 'm5a', 'm5': 'm5a', 'm6i': 'm6a', 'm7i': 'm7a',
    'c4': 'c5a', 'c5': 'c5a', 'c6i': 'c6a',
    'r4': 'r5a', 'r5': 'r5a', 'r6i': 'r6a',
}

def get_size_index(size):
    try:
        return SIZE_ORDER.index(size)
    except ValueError:
        return -1

def instance_exists(itype):
    """Verificar si un tipo de instancia existe en la region"""
    try:
        result = subprocess.run([
            'aws', 'ec2', 'describe-instance-types',
            '--region', region,
            '--instance-types', itype,
            '--query', 'InstanceTypes[0].InstanceType',
            '--output', 'text'
        ], capture_output=True, text=True, timeout=10)
        return result.stdout.strip() not in ('None', '')
    except:
        return False

def get_price_for_type(itype):
    """Obtener precio, primero del cache, luego de la API"""
    if itype in prices and prices[itype] > 0:
        return prices[itype]
    try:
        result = subprocess.run([
            'aws', 'pricing', 'get-products',
            '--region', 'us-east-1',
            '--service-code', 'AmazonEC2',
            '--filters',
            f'Type=TERM_MATCH,Field=instanceType,Value={itype}',
            'Type=TERM_MATCH,Field=location,Value=EU (Frankfurt)',
            'Type=TERM_MATCH,Field=operatingSystem,Value=Linux',
            'Type=TERM_MATCH,Field=tenancy,Value=Shared',
            'Type=TERM_MATCH,Field=preInstalledSw,Value=NA',
            'Type=TERM_MATCH,Field=capacitystatus,Value=Used',
            '--query', 'PriceList[0]',
            '--output', 'text'
        ], capture_output=True, text=True, timeout=30)
        data = json.loads(result.stdout.strip())
        terms = data['terms']['OnDemand']
        for k in terms:
            for sk in terms[k]['priceDimensions']:
                price = float(terms[k]['priceDimensions'][sk]['pricePerUnit']['USD'])
                if price > 0:
                    prices[itype] = price
                    return price
    except:
        pass
    return 0.0

def get_cpu_stats(instance_id):
    """Obtener CPU avg y max de CloudWatch (30 dias)"""
    try:
        result = subprocess.run([
            'aws', 'cloudwatch', 'get-metric-statistics',
            '--region', region,
            '--namespace', 'AWS/EC2',
            '--metric-name', 'CPUUtilization',
            '--dimensions', f'Name=InstanceId,Value={instance_id}',
            '--start-time', start_date,
            '--end-time', end_date,
            '--period', '86400',
            '--statistics', 'Average', 'Maximum',
            '--output', 'json'
        ], capture_output=True, text=True, timeout=30)
        data = json.loads(result.stdout)
        dps = data.get('Datapoints', [])
        if not dps:
            return None, None
        avg = sum(d['Average'] for d in dps) / len(dps)
        mx = max(d['Maximum'] for d in dps)
        return avg, mx
    except:
        return None, None

def recommend_type(current_type, cpu_avg, cpu_max):
    """
    Recomendar tipo optimo basado en uso real de CPU.
    - Si CPU avg < 5%: bajar 3 tamanos
    - Si CPU avg < 10%: bajar 2 tamanos
    - Si CPU avg < 20% y max < 50%: bajar 1 tamano
    - Ademas, sugerir familia AMD mas barata si existe
    """
    family = current_type.split('.')[0]
    size = current_type.split('.')[1]
    current_idx = get_size_index(size)

    if current_idx <= 0:
        return current_type  # Ya es nano o desconocido

    # Determinar cuantos pasos bajar
    steps = 0
    if cpu_avg < 5 and cpu_max < 30:
        steps = 3
    elif cpu_avg < 10 and cpu_max < 40:
        steps = 2
    elif cpu_avg < 20 and cpu_max < 50:
        steps = 1
    elif cpu_avg < 30 and cpu_max < 60:
        steps = 1

    if steps == 0:
        return current_type

    # Bajar tamano dentro de la misma familia
    target_idx = max(0, current_idx - steps)
    candidate_family = family
    candidate_size = SIZE_ORDER[target_idx]

    # Intentar familia AMD mas barata
    cheaper = CHEAPER_FAMILY.get(family, family)
    if cheaper != family:
        cheaper_candidate = f"{cheaper}.{candidate_size}"
        if instance_exists(cheaper_candidate):
            candidate_family = cheaper
        else:
            # Si no existe en AMD, probar misma familia
            candidate_family = family

    candidate = f"{candidate_family}.{candidate_size}"

    # Verificar que existe, si no subir un tamano
    if not instance_exists(candidate):
        for fallback_idx in range(target_idx + 1, current_idx + 1):
            fallback = f"{candidate_family}.{SIZE_ORDER[fallback_idx]}"
            if instance_exists(fallback):
                return fallback
            fallback2 = f"{family}.{SIZE_ORDER[fallback_idx]}"
            if instance_exists(fallback2):
                return fallback2
        return current_type

    return candidate

# ============================================================================
# PROCESAR CADA INSTANCIA
# ============================================================================
results = []
total_current = 0.0
total_optimized = 0.0
total_savings = 0.0
count_over = 0
count_ok = 0
count_under = 0
count_nodata = 0
ri_types = []  # tipos optimizados para plan RI

total = len(instances)
for idx, inst in enumerate(instances):
    inst_id = inst['Id']
    inst_type = inst['Type']
    inst_name = inst.get('Name') or 'sin-nombre'

    print(f"[{idx+1}/{total}] Analizando: {inst_name}...", file=sys.stderr)

    # Specs
    sp = specs.get(inst_type, {})
    vcpus = sp.get('vCPUs', '?')
    ram_mib = sp.get('RAM', 0)
    ram_gib = f"{ram_mib/1024:.1f}" if ram_mib else "?"

    # Precio
    hour_price = get_price_for_type(inst_type)
    monthly_cost = hour_price * 730

    # CPU
    cpu_avg, cpu_max = get_cpu_stats(inst_id)

    # Diagnostico
    if cpu_avg is None:
        verdict = "SIN DATOS"
        verdict_text = "Sin metricas CloudWatch disponibles"
        recommended = inst_type
        savings = 0.0
        count_nodata += 1
    elif cpu_avg <= 30 and cpu_max <= 60:
        # Potencialmente sobredimensionada
        recommended = recommend_type(inst_type, cpu_avg, cpu_max)
        if recommended != inst_type:
            verdict = "SOBREDIMENSIONADA"
            rec_price = get_price_for_type(recommended)
            rec_monthly = rec_price * 730
            savings = monthly_cost - rec_monthly
            if savings < 0:
                savings = 0
                recommended = inst_type
                verdict = "ADECUADA"
                verdict_text = "Dimensionamiento correcto"
                count_ok += 1
            else:
                rec_sp_vcpus = "?"
                rec_sp_ram = "?"
                # Intentar obtener specs del recomendado
                try:
                    r = subprocess.run([
                        'aws', 'ec2', 'describe-instance-types',
                        '--region', region,
                        '--instance-types', recommended,
                        '--query', 'InstanceTypes[0].[VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB]',
                        '--output', 'json'
                    ], capture_output=True, text=True, timeout=10)
                    rd = json.loads(r.stdout)
                    rec_sp_vcpus = rd[0]
                    rec_sp_ram = f"{rd[1]/1024:.1f}"
                except:
                    pass
                verdict_text = f"Reducir a {recommended} ({rec_sp_vcpus} vCPUs, {rec_sp_ram} GiB) -> ahorro ${savings:.2f}/mes"
                count_over += 1
        else:
            verdict = "ADECUADA"
            verdict_text = "Dimensionamiento correcto"
            savings = 0.0
            count_ok += 1
    elif cpu_avg <= 50:
        verdict = "ADECUADA"
        verdict_text = "Dimensionamiento correcto"
        recommended = inst_type
        savings = 0.0
        count_ok += 1
    else:
        verdict = "INFRADIMENSIONADA"
        verdict_text = f"Considerar ampliar (CPU promedio {cpu_avg:.1f}%)"
        recommended = inst_type
        savings = 0.0
        count_under += 1

    total_current += monthly_cost
    if verdict == "SOBREDIMENSIONADA":
        rec_price = get_price_for_type(recommended)
        total_optimized += rec_price * 730
        total_savings += savings
        ri_types.append(recommended)
    else:
        total_optimized += monthly_cost
        ri_types.append(inst_type)

    # Formatear linea
    cpu_avg_str = f"{cpu_avg:.1f}" if cpu_avg is not None else "N/A"
    cpu_max_str = f"{cpu_max:.1f}" if cpu_max is not None else "N/A"

    results.append({
        'name': inst_name, 'id': inst_id, 'type': inst_type,
        'vcpus': vcpus, 'ram': ram_gib,
        'hour_price': hour_price, 'monthly': monthly_cost,
        'cpu_avg': cpu_avg_str, 'cpu_max': cpu_max_str,
        'verdict': verdict, 'verdict_text': verdict_text,
        'savings': savings, 'recommended': recommended
    })

# ============================================================================
# GENERAR SALIDA
# ============================================================================

lines = []
lines.append("============================================================================")
lines.append("                        DETALLE POR INSTANCIA")
lines.append("============================================================================")

for r in results:
    lines.append("")
    lines.append("  ---------------------------------------------------------------------------")
    lines.append(f"  Instancia:       {r['name']}")
    lines.append(f"  ID:              {r['id']}")
    lines.append(f"  Tipo actual:     {r['type']} ({r['vcpus']} vCPUs, {r['ram']} GiB RAM)")
    lines.append(f"  Coste On-Demand: ${r['monthly']:.2f}/mes (${r['hour_price']:.4f}/hora)")
    lines.append(f"  CPU promedio:    {r['cpu_avg']}%  |  CPU maximo: {r['cpu_max']}%")
    lines.append(f"  Diagnostico:     {r['verdict']}")
    lines.append(f"  Recomendacion:   {r['verdict_text']}")
    if r['savings'] > 0:
        lines.append(f"  Ahorro:          ${r['savings']:.2f}/mes")

# Resumen ejecutivo
lines.append("")
lines.append("============================================================================")
lines.append("                        RESUMEN EJECUTIVO")
lines.append("============================================================================")
lines.append("")
lines.append(f"  Total instancias analizadas:     {len(instances)}")
lines.append(f"  Sobredimensionadas:              {count_over} (candidatas a reduccion)")
lines.append(f"  Adecuadas:                       {count_ok} (dimensionamiento correcto)")
lines.append(f"  Infradimensionadas:              {count_under} (considerar ampliar)")
lines.append(f"  Sin datos:                       {count_nodata}")
lines.append("")
lines.append(f"  Coste mensual actual (On-Demand):  ${total_current:.2f}/mes")
lines.append(f"  Coste mensual optimizado:          ${total_optimized:.2f}/mes")
lines.append(f"  Ahorro por right-sizing:           ${total_savings:.2f}/mes")
lines.append(f"  Ahorro anual por right-sizing:     ${total_savings * 12:.2f}/ano")
pct_rs = (total_savings / total_current * 100) if total_current > 0 else 0
lines.append(f"  Porcentaje ahorro right-sizing:    {pct_rs:.1f}%")
lines.append("")

# Plan de Reserved Instances
lines.append("============================================================================")
lines.append("               PLAN DE RESERVED INSTANCES (tras right-sizing)")
lines.append("============================================================================")
lines.append("")

ri_1y_no  = total_optimized * 0.64
ri_1y_all = total_optimized * 0.60
ri_3y_no  = total_optimized * 0.50
ri_3y_all = total_optimized * 0.40

lines.append("  MODALIDAD                          COSTE/MES     AHORRO/MES    AHORRO/ANO")
lines.append("  --------------------------------------------------------------------------")
lines.append(f"  On-Demand (optimizado)             ${total_optimized:>10.2f}    ${'0.00':>10}    ${'0.00':>10}")
save = total_optimized - ri_1y_no
lines.append(f"  RI 1 ano - No Upfront (~36%)       ${ri_1y_no:>10.2f}    ${save:>10.2f}    ${save*12:>10.2f}")
save = total_optimized - ri_1y_all
lines.append(f"  RI 1 ano - All Upfront (~40%)      ${ri_1y_all:>10.2f}    ${save:>10.2f}    ${save*12:>10.2f}")
save = total_optimized - ri_3y_no
lines.append(f"  RI 3 anos - No Upfront (~50%)      ${ri_3y_no:>10.2f}    ${save:>10.2f}    ${save*12:>10.2f}")
save = total_optimized - ri_3y_all
lines.append(f"  RI 3 anos - All Upfront (~60%)     ${ri_3y_all:>10.2f}    ${save:>10.2f}    ${save*12:>10.2f}")
lines.append("  --------------------------------------------------------------------------")
lines.append("")

# Desglose RIs por tipo
from collections import Counter
type_counts = Counter(ri_types)

lines.append("  DESGLOSE: Reserved Instances recomendadas (tipos optimizados):")
lines.append("")
lines.append(f"  {'TIPO INSTANCIA':<24} {'CANT':>4}   {'ON-DEMAND/MES':>14}   {'RI 1Y ALL/MES':>14}")
lines.append("  --------------------------------------------------------------------------")

ri_total_od = 0.0
ri_total_ri = 0.0
for rtype in sorted(type_counts.keys()):
    cnt = type_counts[rtype]
    rprice = get_price_for_type(rtype)
    rod = rprice * 730 * cnt
    rri = rod * 0.60
    ri_total_od += rod
    ri_total_ri += rri
    lines.append(f"  {rtype:<24} {cnt:>4}   ${rod:>13.2f}   ${rri:>13.2f}")

ri_total_save = ri_total_od - ri_total_ri
lines.append("  --------------------------------------------------------------------------")
lines.append(f"  {'TOTAL':<24} {len(ri_types):>4}   ${ri_total_od:>13.2f}   ${ri_total_ri:>13.2f}")
lines.append("")

# Ahorro total combinado
lines.append("============================================================================")
lines.append("                  AHORRO TOTAL COMBINADO")
lines.append("============================================================================")
lines.append("")
combined = total_savings + ri_total_save
current_annual = total_current * 12
final_monthly = ri_total_ri
final_annual = final_monthly * 12
pct_total = (combined / total_current * 100) if total_current > 0 else 0

lines.append(f"  Coste actual (On-Demand):           ${total_current:.2f}/mes  (${current_annual:.2f}/ano)")
lines.append(f"  Coste final (right-size + RI 1Y):   ${final_monthly:.2f}/mes  (${final_annual:.2f}/ano)")
lines.append("")
lines.append(f"  Ahorro por right-sizing:            ${total_savings:.2f}/mes")
lines.append(f"  Ahorro por Reserved Instances:      ${ri_total_save:.2f}/mes")
lines.append(f"  AHORRO TOTAL:                       ${combined:.2f}/mes  (${combined*12:.2f}/ano)")
lines.append(f"  Porcentaje de ahorro:               {pct_total:.1f}%")
lines.append("")
lines.append("============================================================================")
lines.append("  CRITERIOS DE CLASIFICACION:")
lines.append("    SOBREDIMENSIONADA:")
lines.append("      CPU avg <  5% y max < 30%: bajar 3 tamanos + familia AMD si existe")
lines.append("      CPU avg < 10% y max < 40%: bajar 2 tamanos + familia AMD si existe")
lines.append("      CPU avg < 20% y max < 50%: bajar 1 tamano")
lines.append("      CPU avg < 30% y max < 60%: bajar 1 tamano")
lines.append("    ADECUADA:          CPU avg entre 30-50%")
lines.append("    INFRADIMENSIONADA: CPU avg > 50%")
lines.append("")
lines.append("  NOTAS:")
lines.append("  - Precios obtenidos de AWS Pricing API (On-Demand, Linux, Frankfurt)")
lines.append("  - Los descuentos RI son aproximados y varian segun el tipo de instancia")
lines.append("  - Se recomienda verificar en AWS Pricing Calculator antes de comprar")
lines.append("  - Para instancias con uso variable considerar Savings Plans")
lines.append("  - Las familias AMD (t3a, m5a, c5a, r5a) son ~10% mas baratas")
lines.append("============================================================================")

# Imprimir todo
for l in lines:
    print(l)

PYEOF
)

# Escribir al archivo y pantalla
echo "$REPORT_BODY" | tee -a "$REPORT_FILE"

echo ""
echo "=========================================="
echo "  Reporte guardado en: ${REPORT_FILE}"
echo "=========================================="
