#!/bin/bash
# ============================================================================
# AWS Cost Optimization Report - Frankfurt (eu-central-1)
# Analiza: EC2, ECS Fargate, EBS volumes, RDS instances
# Uso: bash aws-cost-optimizer.sh
# Salida: aws-cost-report-YYYY-MM-DD.txt
# ============================================================================

REGION="eu-central-1"
DAYS=30
END_DATE=$(date -u +%Y-%m-%dT00:00:00Z)
START_DATE=$(date -u -d "${DAYS} days ago" +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u -v-${DAYS}d +%Y-%m-%dT00:00:00Z)
REPORT_FILE="aws-cost-report-$(date +%Y-%m-%d).txt"

rm -f /tmp/ec2price_* 2>/dev/null

> "$REPORT_FILE"
out() {
  echo "$1"
  echo "$1" >> "$REPORT_FILE"
}

out "============================================================================"
out "  AWS COST OPTIMIZATION REPORT"
out "  Region: ${REGION} (Frankfurt)"
out "  Periodo analizado: ultimos ${DAYS} dias"
out "  Generado: $(date '+%Y-%m-%d %H:%M:%S')"
out "============================================================================"

# ============================================================================
# Recopilar datos de todos los servicios en paralelo
# ============================================================================
echo ""
echo "Recopilando datos de AWS (EC2, ECS, EBS, RDS)..."

# EC2 instances
EC2_JSON=$(aws ec2 describe-instances \
  --region "${REGION}" \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,Name:Tags[?Key==`Name`].Value|[0]}' \
  --output json 2>/dev/null || echo "[]")

# EC2 instance types specs
EC2_TYPES=$(echo "$EC2_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for t in sorted(set(i['Type'] for i in data)):
    print(t)
" 2>/dev/null)
ALL_TYPES=$(echo "$EC2_TYPES" | tr '\n' ' ')
EC2_SPECS=$(aws ec2 describe-instance-types \
  --region "${REGION}" \
  --instance-types $ALL_TYPES \
  --query 'InstanceTypes[].{Type:InstanceType,vCPUs:VCpuInfo.DefaultVCpus,RAM:MemoryInfo.SizeInMiB}' \
  --output json 2>/dev/null || echo "[]")

# ECS clusters y services
ECS_CLUSTERS=$(aws ecs list-clusters --region "${REGION}" --query 'clusterArns' --output json 2>/dev/null || echo "[]")

# EBS volumes
EBS_JSON=$(aws ec2 describe-volumes \
  --region "${REGION}" \
  --query 'Volumes[].{Id:VolumeId,Size:Size,Type:VolumeType,State:State,Iops:Iops,AZ:AvailabilityZone,Attachments:Attachments[0].InstanceId,Name:Tags[?Key==`Name`].Value|[0]}' \
  --output json 2>/dev/null || echo "[]")

# RDS instances
RDS_JSON=$(aws rds describe-db-instances \
  --region "${REGION}" \
  --query 'DBInstances[].{Id:DBInstanceIdentifier,Class:DBInstanceClass,Engine:Engine,MultiAZ:MultiAZ,Storage:AllocatedStorage,StorageType:StorageType,Iops:Iops,Status:DBInstanceStatus}' \
  --output json 2>/dev/null || echo "[]")

echo "Datos recopilados. Analizando..."

# ============================================================================
# ANALISIS COMPLETO EN PYTHON3
# ============================================================================

REPORT_BODY=$(EC2_JSON="$EC2_JSON" EC2_SPECS="$EC2_SPECS" ECS_CLUSTERS="$ECS_CLUSTERS" EBS_JSON="$EBS_JSON" RDS_JSON="$RDS_JSON" REGION="$REGION" START_DATE="$START_DATE" END_DATE="$END_DATE" python3 << 'PYEOF'
import subprocess, json, sys, os
from collections import Counter

region = os.environ['REGION']
start_date = os.environ['START_DATE']
end_date = os.environ['END_DATE']

lines = []
grand_total_current = 0.0
grand_total_savings = 0.0

# ---- Utilidades ----
def get_ec2_price(itype, cache={}):
    if itype in cache:
        return cache[itype]
    try:
        r = subprocess.run([
            'aws', 'pricing', 'get-products', '--region', 'us-east-1',
            '--service-code', 'AmazonEC2', '--filters',
            f'Type=TERM_MATCH,Field=instanceType,Value={itype}',
            'Type=TERM_MATCH,Field=location,Value=EU (Frankfurt)',
            'Type=TERM_MATCH,Field=operatingSystem,Value=Linux',
            'Type=TERM_MATCH,Field=tenancy,Value=Shared',
            'Type=TERM_MATCH,Field=preInstalledSw,Value=NA',
            'Type=TERM_MATCH,Field=capacitystatus,Value=Used',
            '--query', 'PriceList[0]', '--output', 'text'
        ], capture_output=True, text=True, timeout=30)
        data = json.loads(r.stdout.strip())
        for k in data['terms']['OnDemand']:
            for sk in data['terms']['OnDemand'][k]['priceDimensions']:
                p = float(data['terms']['OnDemand'][k]['priceDimensions'][sk]['pricePerUnit']['USD'])
                if p > 0:
                    cache[itype] = p
                    return p
    except:
        pass
    cache[itype] = 0.0
    return 0.0

def get_cpu(instance_id):
    try:
        r = subprocess.run([
            'aws', 'cloudwatch', 'get-metric-statistics', '--region', region,
            '--namespace', 'AWS/EC2', '--metric-name', 'CPUUtilization',
            '--dimensions', f'Name=InstanceId,Value={instance_id}',
            '--start-time', start_date, '--end-time', end_date,
            '--period', '86400', '--statistics', 'Average', 'Maximum',
            '--output', 'json'
        ], capture_output=True, text=True, timeout=30)
        dps = json.loads(r.stdout).get('Datapoints', [])
        if not dps:
            return None, None
        return sum(d['Average'] for d in dps)/len(dps), max(d['Maximum'] for d in dps)
    except:
        return None, None

def instance_exists(itype, cache={}):
    if itype in cache:
        return cache[itype]
    try:
        r = subprocess.run([
            'aws', 'ec2', 'describe-instance-types', '--region', region,
            '--instance-types', itype, '--query', 'InstanceTypes[0].InstanceType',
            '--output', 'text'
        ], capture_output=True, text=True, timeout=10)
        exists = r.stdout.strip() not in ('None', '')
        cache[itype] = exists
        return exists
    except:
        cache[itype] = False
        return False

SIZE_ORDER = ['nano','micro','small','medium','large','xlarge','2xlarge',
              '4xlarge','8xlarge','9xlarge','12xlarge','16xlarge','24xlarge','metal']
CHEAPER = {'t2':'t3a','t3':'t3a','m4':'m5a','m5':'m5a','m6i':'m6a','m7i':'m7a',
           'c4':'c5a','c5':'c5a','c6i':'c6a','r4':'r5a','r5':'r5a','r6i':'r6a'}

def recommend_ec2(ctype, cpu_avg, cpu_max):
    parts = ctype.split('.')
    if len(parts) != 2:
        return ctype
    family, size = parts
    try:
        cidx = SIZE_ORDER.index(size)
    except ValueError:
        return ctype
    if cidx <= 0:
        return ctype
    steps = 0
    if cpu_avg < 5 and cpu_max < 30: steps = 3
    elif cpu_avg < 10 and cpu_max < 40: steps = 2
    elif cpu_avg < 30 and cpu_max < 60: steps = 1
    if steps == 0:
        return ctype
    tidx = max(0, cidx - steps)
    tsize = SIZE_ORDER[tidx]
    cheaper_fam = CHEAPER.get(family, family)
    if cheaper_fam != family and instance_exists(f"{cheaper_fam}.{tsize}"):
        candidate = f"{cheaper_fam}.{tsize}"
    else:
        candidate = f"{family}.{tsize}"
    if instance_exists(candidate):
        return candidate
    for fi in range(tidx+1, cidx+1):
        fb = f"{family}.{SIZE_ORDER[fi]}"
        if instance_exists(fb):
            return fb
    return ctype

# ########################################################################
# SECCION 1: EC2 INSTANCES
# ########################################################################
lines.append("")
lines.append("============================================================================")
lines.append("  SECCION 1: EC2 INSTANCES")
lines.append("============================================================================")

instances = json.loads(os.environ['EC2_JSON'])
specs_list = json.loads(os.environ['EC2_SPECS'])
specs = {s['Type']: s for s in specs_list}

ec2_current = 0.0
ec2_savings = 0.0
ec2_optimized = 0.0
ec2_over = 0
ec2_ok = 0
ec2_ri_types = []

total = len(instances)
for idx, inst in enumerate(instances):
    iid, itype, iname = inst['Id'], inst['Type'], inst.get('Name') or 'sin-nombre'
    print(f"  EC2 [{idx+1}/{total}] {iname}...", file=sys.stderr)

    sp = specs.get(itype, {})
    vcpus = sp.get('vCPUs', '?')
    ram_mib = sp.get('RAM', 0)
    ram_gib = f"{ram_mib/1024:.1f}" if ram_mib else "?"

    hp = get_ec2_price(itype)
    monthly = hp * 730
    cpu_avg, cpu_max = get_cpu(iid)

    if cpu_avg is None:
        verdict, vtext, rec, sav = "SIN DATOS", "Sin metricas", itype, 0.0
    elif cpu_avg <= 30 and cpu_max <= 60:
        rec = recommend_ec2(itype, cpu_avg, cpu_max)
        if rec != itype:
            rp = get_ec2_price(rec)
            sav = monthly - rp * 730
            if sav <= 0:
                verdict, vtext, rec, sav = "ADECUADA", "OK", itype, 0.0
                ec2_ok += 1
            else:
                # Get rec specs
                rvc, rrm = "?", "?"
                try:
                    r = subprocess.run(['aws','ec2','describe-instance-types','--region',region,
                        '--instance-types',rec,'--query','InstanceTypes[0].[VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB]',
                        '--output','json'], capture_output=True, text=True, timeout=10)
                    rd = json.loads(r.stdout)
                    rvc, rrm = rd[0], f"{rd[1]/1024:.1f}"
                except: pass
                verdict = "SOBREDIMENSIONADA"
                vtext = f"Reducir a {rec} ({rvc} vCPUs, {rrm} GiB) -> ahorro ${sav:.2f}/mes"
                ec2_over += 1
        else:
            verdict, vtext, sav = "ADECUADA", "Dimensionamiento correcto", 0.0
            ec2_ok += 1
    elif cpu_avg <= 50:
        verdict, vtext, rec, sav = "ADECUADA", "OK", itype, 0.0
        ec2_ok += 1
    else:
        verdict, vtext, rec, sav = "INFRADIMENSIONADA", f"CPU avg {cpu_avg:.0f}%", itype, 0.0

    ec2_current += monthly
    ec2_savings += sav
    if sav > 0:
        ec2_optimized += get_ec2_price(rec) * 730
        ec2_ri_types.append(rec)
    else:
        ec2_optimized += monthly
        ec2_ri_types.append(itype)

    ca = f"{cpu_avg:.1f}" if cpu_avg is not None else "N/A"
    cm = f"{cpu_max:.1f}" if cpu_max is not None else "N/A"
    lines.append(f"\n  {iname} ({iid})")
    lines.append(f"    Tipo: {itype} ({vcpus} vCPUs, {ram_gib} GiB) | ${monthly:.2f}/mes")
    lines.append(f"    CPU avg: {ca}% | max: {cm}% | {verdict}")
    if sav > 0:
        lines.append(f"    >> {vtext}")

lines.append(f"\n  EC2 SUBTOTAL: ${ec2_current:.2f}/mes | Ahorro: ${ec2_savings:.2f}/mes | {ec2_over} sobredimensionadas de {total}")
grand_total_current += ec2_current
grand_total_savings += ec2_savings

# ########################################################################
# SECCION 2: ECS FARGATE
# ########################################################################
lines.append("")
lines.append("============================================================================")
lines.append("  SECCION 2: ECS FARGATE")
lines.append("============================================================================")

clusters = json.loads(os.environ['ECS_CLUSTERS'])
ecs_current = 0.0
ecs_savings = 0.0
ecs_total_services = 0
ecs_over = 0

# Precios Fargate Frankfurt (por hora)
FARGATE_VCPU_HOUR = 0.04656
FARGATE_GB_HOUR = 0.00511

for cluster_arn in clusters:
    cluster_name = cluster_arn.split('/')[-1]
    print(f"  ECS cluster: {cluster_name}...", file=sys.stderr)

    # Listar servicios
    try:
        r = subprocess.run([
            'aws', 'ecs', 'list-services', '--region', region,
            '--cluster', cluster_arn, '--query', 'serviceArns', '--output', 'json'
        ], capture_output=True, text=True, timeout=30)
        service_arns = json.loads(r.stdout)
    except:
        service_arns = []

    if not service_arns:
        lines.append(f"\n  Cluster: {cluster_name} - Sin servicios")
        continue

    # Describir servicios (en lotes de 10)
    for batch_start in range(0, len(service_arns), 10):
        batch = service_arns[batch_start:batch_start+10]
        try:
            r = subprocess.run([
                'aws', 'ecs', 'describe-services', '--region', region,
                '--cluster', cluster_arn, '--services'] + batch + [
                '--query', 'services[].{Name:serviceName,TaskDef:taskDefinition,Desired:desiredCount,Running:runningCount,Launch:launchType}',
                '--output', 'json'
            ], capture_output=True, text=True, timeout=30)
            services = json.loads(r.stdout)
        except:
            continue

        for svc in services:
            sname = svc['Name']
            desired = svc.get('Desired', 0)
            running = svc.get('Running', 0)
            launch = svc.get('Launch', 'UNKNOWN')
            taskdef = svc.get('TaskDef', '')
            ecs_total_services += 1

            if launch != 'FARGATE' and 'FARGATE' not in str(launch):
                lines.append(f"\n  {cluster_name}/{sname} - Launch: {launch} (no Fargate, omitido)")
                continue

            # Obtener task definition para CPU/RAM
            try:
                r = subprocess.run([
                    'aws', 'ecs', 'describe-task-definition', '--region', region,
                    '--task-definition', taskdef,
                    '--query', 'taskDefinition.{Cpu:cpu,Memory:memory}',
                    '--output', 'json'
                ], capture_output=True, text=True, timeout=15)
                td = json.loads(r.stdout)
                task_cpu = int(td.get('Cpu', 0) or 0)  # en unidades (256=0.25vCPU)
                task_mem = int(td.get('Memory', 0) or 0)  # en MiB
            except:
                task_cpu, task_mem = 0, 0

            vcpu = task_cpu / 1024
            mem_gb = task_mem / 1024

            # Coste mensual: precio/hora * 730 horas * tasks
            svc_monthly = (vcpu * FARGATE_VCPU_HOUR + mem_gb * FARGATE_GB_HOUR) * 730 * desired
            ecs_current += svc_monthly

            # Obtener CPU del servicio via CloudWatch
            svc_cpu_avg = None
            try:
                r = subprocess.run([
                    'aws', 'cloudwatch', 'get-metric-statistics', '--region', region,
                    '--namespace', 'AWS/ECS', '--metric-name', 'CPUUtilization',
                    '--dimensions', f'Name=ClusterName,Value={cluster_name}',
                    f'Name=ServiceName,Value={sname}',
                    '--start-time', start_date, '--end-time', end_date,
                    '--period', '86400', '--statistics', 'Average',
                    '--output', 'json'
                ], capture_output=True, text=True, timeout=30)
                dps = json.loads(r.stdout).get('Datapoints', [])
                if dps:
                    svc_cpu_avg = sum(d['Average'] for d in dps) / len(dps)
            except:
                pass

            # Analisis
            savings = 0.0
            rec_text = ""
            if svc_cpu_avg is not None and svc_cpu_avg < 20 and vcpu >= 0.5:
                # Recomendar bajar CPU a la mitad
                new_vcpu = max(0.25, vcpu / 2)
                new_mem = max(0.5, mem_gb / 2)
                new_monthly = (new_vcpu * FARGATE_VCPU_HOUR + new_mem * FARGATE_GB_HOUR) * 730 * desired
                savings = svc_monthly - new_monthly
                rec_text = f"Reducir a {new_vcpu:.2f} vCPU / {new_mem:.1f} GB -> ahorro ${savings:.2f}/mes"
                ecs_over += 1
            elif svc_cpu_avg is not None and svc_cpu_avg < 10 and vcpu >= 0.25:
                new_vcpu = max(0.25, vcpu / 4)
                new_mem = max(0.5, mem_gb / 4)
                new_monthly = (new_vcpu * FARGATE_VCPU_HOUR + new_mem * FARGATE_GB_HOUR) * 730 * desired
                savings = svc_monthly - new_monthly
                rec_text = f"Reducir a {new_vcpu:.2f} vCPU / {new_mem:.1f} GB -> ahorro ${savings:.2f}/mes"
                ecs_over += 1

            ecs_savings += savings

            cpu_str = f"{svc_cpu_avg:.1f}%" if svc_cpu_avg is not None else "N/A"
            verdict = "SOBREDIMENSIONADA" if savings > 0 else "OK"
            lines.append(f"\n  {cluster_name}/{sname}")
            lines.append(f"    Tasks: {desired} | {vcpu:.2f} vCPU, {mem_gb:.1f} GB | ${svc_monthly:.2f}/mes")
            lines.append(f"    CPU avg: {cpu_str} | {verdict}")
            if savings > 0:
                lines.append(f"    >> {rec_text}")

lines.append(f"\n  ECS SUBTOTAL: ${ecs_current:.2f}/mes | Ahorro: ${ecs_savings:.2f}/mes | {ecs_over} sobredimensionados de {ecs_total_services}")
grand_total_current += ecs_current
grand_total_savings += ecs_savings

# ########################################################################
# SECCION 3: EBS VOLUMES
# ########################################################################
lines.append("")
lines.append("============================================================================")
lines.append("  SECCION 3: EBS VOLUMES")
lines.append("============================================================================")

volumes = json.loads(os.environ['EBS_JSON'])
ebs_current = 0.0
ebs_savings = 0.0
ebs_idle = 0
ebs_oversized = 0

# Precios EBS Frankfurt (USD/GB/mes)
EBS_PRICES = {'gp2': 0.119, 'gp3': 0.0952, 'io1': 0.149, 'io2': 0.149,
              'st1': 0.054, 'sc1': 0.030, 'standard': 0.055}
EBS_IOPS_PRICE = {'io1': 0.078, 'io2': 0.078}

for vol in volumes:
    vid = vol['Id']
    vsize = vol['Size']
    vtype = vol['Type']
    vstate = vol['State']
    attached = vol.get('Attachments')
    vname = vol.get('Name') or vid
    viops = vol.get('Iops', 0) or 0

    # Coste mensual
    price_gb = EBS_PRICES.get(vtype, 0.119)
    iops_cost = 0
    if vtype in EBS_IOPS_PRICE and viops > 0:
        iops_cost = viops * EBS_IOPS_PRICE[vtype]
    monthly = vsize * price_gb + iops_cost
    ebs_current += monthly

    savings = 0.0
    verdict = "OK"

    if vstate == 'available' or not attached:
        # Volume no attached = IDLE
        verdict = "IDLE (no attached)"
        savings = monthly
        ebs_idle += 1
    elif vtype == 'gp2':
        # gp2 -> gp3 ahorra ~20%
        new_monthly = vsize * EBS_PRICES['gp3']
        savings = monthly - new_monthly
        verdict = "Migrar gp2 -> gp3"
        ebs_oversized += 1
    elif vtype in ('io1', 'io2'):
        # Verificar si realmente necesita provisioned IOPS
        try:
            r = subprocess.run([
                'aws', 'cloudwatch', 'get-metric-statistics', '--region', region,
                '--namespace', 'AWS/EBS', '--metric-name', 'VolumeReadOps',
                '--dimensions', f'Name=VolumeId,Value={vid}',
                '--start-time', start_date, '--end-time', end_date,
                '--period', str(30*86400), '--statistics', 'Sum', '--output', 'json'
            ], capture_output=True, text=True, timeout=15)
            dps = json.loads(r.stdout).get('Datapoints', [])
            total_ops = sum(d['Sum'] for d in dps)
            if total_ops < 100000:  # Muy pocas ops -> migrar a gp3
                new_monthly = vsize * EBS_PRICES['gp3']
                savings = monthly - new_monthly
                verdict = f"Bajo IOPS real -> migrar a gp3"
                ebs_oversized += 1
        except:
            pass

    ebs_savings += savings

    if savings > 0:
        lines.append(f"\n  {vname} ({vid})")
        lines.append(f"    {vtype} | {vsize} GB | ${monthly:.2f}/mes | {verdict}")
        lines.append(f"    >> Ahorro: ${savings:.2f}/mes")

# Mostrar tambien resumen de los que estan OK
ok_count = len(volumes) - ebs_idle - ebs_oversized
lines.append(f"\n  EBS SUBTOTAL: ${ebs_current:.2f}/mes | Ahorro: ${ebs_savings:.2f}/mes")
lines.append(f"    {ebs_idle} volumes idle, {ebs_oversized} optimizables, {ok_count} OK de {len(volumes)} total")
grand_total_current += ebs_current
grand_total_savings += ebs_savings

# ########################################################################
# SECCION 4: RDS INSTANCES
# ########################################################################
lines.append("")
lines.append("============================================================================")
lines.append("  SECCION 4: RDS INSTANCES")
lines.append("============================================================================")

rds_instances = json.loads(os.environ['RDS_JSON'])
rds_current = 0.0
rds_savings = 0.0
rds_over = 0

# Precios RDS: se obtienen de AWS Pricing API (no hardcoded)
RDS_PRICES = {}
def get_rds_price(dbclass, engine='MySQL', cache=RDS_PRICES):
    if dbclass in cache:
        return cache[dbclass]
    # Mapear engine a Pricing API format
    engine_map = {
        'mysql': 'MySQL', 'mariadb': 'MariaDB', 'postgres': 'PostgreSQL',
        'aurora-mysql': 'Aurora MySQL', 'aurora-postgresql': 'Aurora PostgreSQL',
        'oracle-ee': 'Oracle', 'oracle-se2': 'Oracle', 'sqlserver-ee': 'SQL Server',
        'sqlserver-se': 'SQL Server', 'sqlserver-ex': 'SQL Server', 'sqlserver-web': 'SQL Server',
    }
    db_engine = engine_map.get(engine.lower(), 'MySQL')
    try:
        r = subprocess.run([
            'aws', 'pricing', 'get-products', '--region', 'us-east-1',
            '--service-code', 'AmazonRDS', '--filters',
            f'Type=TERM_MATCH,Field=instanceType,Value={dbclass}',
            'Type=TERM_MATCH,Field=location,Value=EU (Frankfurt)',
            f'Type=TERM_MATCH,Field=databaseEngine,Value={db_engine}',
            'Type=TERM_MATCH,Field=deploymentOption,Value=Single-AZ',
            '--query', 'PriceList[0]', '--output', 'text'
        ], capture_output=True, text=True, timeout=30)
        data = json.loads(r.stdout.strip())
        for k in data['terms']['OnDemand']:
            for sk in data['terms']['OnDemand'][k]['priceDimensions']:
                p = float(data['terms']['OnDemand'][k]['priceDimensions'][sk]['pricePerUnit']['USD'])
                if p > 0:
                    cache[dbclass] = p
                    return p
    except:
        pass
    cache[dbclass] = 0.0
    return 0.0
RDS_STORAGE_PRICES = {'gp2': 0.133, 'gp3': 0.111, 'io1': 0.149, 'standard': 0.055}
RDS_DOWNGRADE = {
    'db.t3.2xlarge':'db.t3.xlarge','db.t3.xlarge':'db.t3.large','db.t3.large':'db.t3.medium',
    'db.t3.medium':'db.t3.small','db.t3.small':'db.t3.micro',
    'db.t2.large':'db.t2.medium','db.t2.medium':'db.t2.small','db.t2.small':'db.t2.micro',
    'db.m5.4xlarge':'db.m5.2xlarge','db.m5.2xlarge':'db.m5.xlarge','db.m5.xlarge':'db.m5.large',
    'db.m6g.2xlarge':'db.m6g.xlarge','db.m6g.xlarge':'db.m6g.large',
    'db.m6i.2xlarge':'db.m6i.xlarge','db.m6i.xlarge':'db.m6i.large',
    'db.r5.4xlarge':'db.r5.2xlarge','db.r5.2xlarge':'db.r5.xlarge','db.r5.xlarge':'db.r5.large',
    'db.r6g.2xlarge':'db.r6g.xlarge','db.r6g.xlarge':'db.r6g.large',
    'db.r6i.xlarge':'db.r6i.large',
    # Cross-family: x86 -> Graviton (mas barato)
    'db.m5.large':'db.m6g.large', 'db.r5.large':'db.r6g.large',
    'db.t3.micro':'db.t4g.micro','db.t3.small':'db.t4g.small',
    'db.t3.medium':'db.t4g.medium','db.t3.large':'db.t4g.large',
}

for rds in rds_instances:
    rid = rds['Id']
    rclass = rds['Class']
    engine = rds['Engine']
    multi_az = rds.get('MultiAZ', False)
    storage = rds.get('Storage', 0)
    stype = rds.get('StorageType', 'gp2')
    status = rds.get('Status', '')

    print(f"  RDS: {rid}...", file=sys.stderr)

    # Coste compute (precio real de AWS Pricing API)
    hp = get_rds_price(rclass, engine)
    compute_monthly = hp * 730
    if multi_az:
        compute_monthly *= 2

    # Coste storage
    sp = RDS_STORAGE_PRICES.get(stype, 0.133)
    storage_monthly = storage * sp

    monthly = compute_monthly + storage_monthly
    rds_current += monthly

    # CPU de CloudWatch
    rds_cpu = None
    try:
        r = subprocess.run([
            'aws', 'cloudwatch', 'get-metric-statistics', '--region', region,
            '--namespace', 'AWS/RDS', '--metric-name', 'CPUUtilization',
            '--dimensions', f'Name=DBInstanceIdentifier,Value={rid}',
            '--start-time', start_date, '--end-time', end_date,
            '--period', '86400', '--statistics', 'Average', 'Maximum',
            '--output', 'json'
        ], capture_output=True, text=True, timeout=30)
        dps = json.loads(r.stdout).get('Datapoints', [])
        if dps:
            rds_cpu = sum(d['Average'] for d in dps) / len(dps)
            rds_cpu_max = max(d['Maximum'] for d in dps)
    except:
        rds_cpu_max = 0

    savings = 0.0
    verdict = "OK"
    rec_text = ""

    # RDS: solo recomendar downgrade si CPU es MUY baja Y la clase es grande
    # Las BBDD son memory-bound, CPU baja es normal en clases small/medium
    rds_size = rclass.split('.')[-1] if '.' in rclass else ''
    is_large_class = rds_size in ('large','xlarge','2xlarge','4xlarge','8xlarge','12xlarge','16xlarge')
    if rds_cpu is not None and rds_cpu < 10 and is_large_class:
        rec_class = RDS_DOWNGRADE.get(rclass, '')
        if rec_class:
            rec_hp = get_rds_price(rec_class, engine)
            if rec_hp > 0:
                rec_compute = rec_hp * 730
                if multi_az:
                    rec_compute *= 2
                rec_monthly = rec_compute + storage_monthly
                savings = monthly - rec_monthly
                if savings > 0:
                    verdict = "SOBREDIMENSIONADA"
                    rec_text = f"Reducir a {rec_class} -> ahorro ${savings:.2f}/mes"
                    rds_over += 1

    # Storage: gp2 -> gp3
    storage_savings = 0.0
    if stype == 'gp2':
        new_storage = storage * RDS_STORAGE_PRICES['gp3']
        storage_savings = storage_monthly - new_storage
        if storage_savings > 0:
            savings += storage_savings

    rds_savings += savings

    cpu_str = f"{rds_cpu:.1f}%" if rds_cpu is not None else "N/A"
    lines.append(f"\n  {rid} ({engine}, {rclass})")
    lines.append(f"    Storage: {storage} GB {stype} | MultiAZ: {multi_az} | ${monthly:.2f}/mes")
    lines.append(f"    CPU avg: {cpu_str} | {verdict}")
    if rec_text:
        lines.append(f"    >> Compute: {rec_text}")
    if storage_savings > 0:
        lines.append(f"    >> Storage: Migrar {stype} -> gp3 -> ahorro ${storage_savings:.2f}/mes")

lines.append(f"\n  RDS SUBTOTAL: ${rds_current:.2f}/mes | Ahorro: ${rds_savings:.2f}/mes | {rds_over} sobredimensionadas de {len(rds_instances)}")
grand_total_current += rds_current
grand_total_savings += rds_savings

# ########################################################################
# RESUMEN EJECUTIVO
# ########################################################################
lines.append("")
lines.append("============================================================================")
lines.append("                        RESUMEN EJECUTIVO")
lines.append("============================================================================")
lines.append("")
lines.append(f"  {'SERVICIO':<25} {'COSTE ACTUAL':>14} {'AHORRO':>14} {'% AHORRO':>10}")
lines.append(f"  {'-'*65}")
for label, cur, sav in [
    ("EC2 Instances", ec2_current, ec2_savings),
    ("ECS Fargate", ecs_current, ecs_savings),
    ("EBS Volumes", ebs_current, ebs_savings),
    ("RDS Instances", rds_current, rds_savings),
]:
    pct = (sav/cur*100) if cur > 0 else 0
    lines.append(f"  {label:<25} ${cur:>12.2f}  ${sav:>12.2f}  {pct:>8.1f}%")

lines.append(f"  {'-'*65}")
pct_total = (grand_total_savings/grand_total_current*100) if grand_total_current > 0 else 0
lines.append(f"  {'TOTAL'::<25} ${grand_total_current:>12.2f}  ${grand_total_savings:>12.2f}  {pct_total:>8.1f}%")
lines.append("")
lines.append(f"  Ahorro mensual total:    ${grand_total_savings:.2f}/mes")
lines.append(f"  Ahorro anual total:      ${grand_total_savings*12:.2f}/ano")
lines.append("")

# ########################################################################
# PLAN DE RESERVED INSTANCES (solo EC2)
# ########################################################################
lines.append("============================================================================")
lines.append("          PLAN DE RESERVED INSTANCES EC2 (tras right-sizing)")
lines.append("============================================================================")
lines.append("")

ri_base = ec2_optimized if ec2_optimized > 0 else ec2_current - ec2_savings
for label, factor in [("On-Demand (optimizado)", 1.0), ("RI 1 ano No Upfront (~36%)", 0.64),
    ("RI 1 ano All Upfront (~40%)", 0.60), ("RI 3 anos No Upfront (~50%)", 0.50),
    ("RI 3 anos All Upfront (~60%)", 0.40)]:
    cost = ri_base * factor
    save = ri_base - cost
    lines.append(f"  {label:<35} ${cost:>10.2f}/mes  ${save:>10.2f}/mes  ${save*12:>10.2f}/ano")
lines.append("")

# Desglose por tipo
tc = Counter(ec2_ri_types)
lines.append(f"  {'TIPO':<24} {'CANT':>4}  {'OD/MES':>12}  {'RI 1Y ALL':>12}")
lines.append(f"  {'-'*56}")
ri_od_total = 0
ri_ri_total = 0
for t in sorted(tc):
    c = tc[t]
    p = get_ec2_price(t)
    od = p * 730 * c
    ri = od * 0.60
    ri_od_total += od
    ri_ri_total += ri
    lines.append(f"  {t:<24} {c:>4}  ${od:>11.2f}  ${ri:>11.2f}")
lines.append(f"  {'-'*56}")
lines.append(f"  {'TOTAL':<24} {len(ec2_ri_types):>4}  ${ri_od_total:>11.2f}  ${ri_ri_total:>11.2f}")
lines.append("")

# ########################################################################
# AHORRO TOTAL COMBINADO
# ########################################################################
lines.append("============================================================================")
lines.append("                  AHORRO TOTAL COMBINADO")
lines.append("============================================================================")
lines.append("")
ri_ec2_save = ri_od_total - ri_ri_total
combined = grand_total_savings + ri_ec2_save
final = grand_total_current - combined
pct = (combined/grand_total_current*100) if grand_total_current > 0 else 0

lines.append(f"  Coste actual total:                 ${grand_total_current:.2f}/mes")
lines.append(f"  Ahorro right-sizing (todos):        ${grand_total_savings:.2f}/mes")
lines.append(f"  Ahorro Reserved Instances (EC2):    ${ri_ec2_save:.2f}/mes")
lines.append(f"  AHORRO TOTAL COMBINADO:             ${combined:.2f}/mes  (${combined*12:.2f}/ano)")
lines.append(f"  Coste final estimado:               ${final:.2f}/mes  (${final*12:.2f}/ano)")
lines.append(f"  Porcentaje de ahorro:               {pct:.1f}%")
lines.append("")
lines.append("============================================================================")
lines.append("  NOTAS:")
lines.append("  - EC2: Precios de AWS Pricing API, right-sizing multi-nivel + AMD")
lines.append("  - ECS: Precios Fargate Frankfurt, right-sizing basado en CPU avg")
lines.append("  - EBS: Deteccion de volumes idle y migracion gp2->gp3")
lines.append("  - RDS: Right-sizing + migracion Graviton + storage gp2->gp3")
lines.append("  - RI: Descuentos aproximados, verificar en AWS Pricing Calculator")
lines.append("============================================================================")

for l in lines:
    print(l)
PYEOF
)

echo "$REPORT_BODY" | tee -a "$REPORT_FILE"

echo ""
echo "=========================================="
echo "  Reporte guardado en: ${REPORT_FILE}"
echo "=========================================="
