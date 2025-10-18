# Configuración de Google Cloud Platform para Túneles SSH IoT

## Resumen

Guía para configurar una VM en GCP como servidor de túneles SSH inversos.

## Paso 1: Crear Instancia de Compute Engine

### Desde Cloud Console

1. Navegar a **Compute Engine** > **VM instances** > **Create Instance**
2. Configuración:
   - **Name**: iot-tunnel-server
   - **Region**: us-central1
   - **Zone**: us-central1-a
   - **Machine type**: e2-small (2 vCPU, 2 GB memoria)
   - **Boot disk**: Ubuntu 22.04 LTS, 20 GB
   - **Firewall**: Allow SSH traffic

### Desde gcloud CLI

```bash
# Configurar proyecto
gcloud config set project PROJECT_ID

# Crear instancia
gcloud compute instances create iot-tunnel-server \
    --zone=us-central1-a \
    --machine-type=e2-small \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=20GB \
    --boot-disk-type=pd-balanced \
    --tags=ssh-server
```

## Paso 2: Configurar Firewall Rules

### Desde Console

1. Ir a **VPC network** > **Firewall** > **Create firewall rule**
2. Configuración:
   - **Name**: allow-ssh-iot-tunnel
   - **Network**: default
   - **Priority**: 1000
   - **Direction**: Ingress
   - **Action**: Allow
   - **Targets**: Specified target tags
   - **Target tags**: ssh-server
   - **Source filter**: IP ranges
   - **Source IP ranges**: 0.0.0.0/0
   - **Protocols and ports**: tcp:22

### Desde gcloud CLI

```bash
# Crear regla de firewall
gcloud compute firewall-rules create allow-ssh-iot-tunnel \
    --network=default \
    --action=allow \
    --direction=ingress \
    --target-tags=ssh-server \
    --source-ranges=0.0.0.0/0 \
    --rules=tcp:22 \
    --priority=1000
```

## Paso 3: Reservar IP Estática

```bash
# Reservar IP externa estática
gcloud compute addresses create iot-tunnel-ip \
    --region=us-central1

# Obtener la IP reservada
IP_ADDRESS=$(gcloud compute addresses describe iot-tunnel-ip \
    --region=us-central1 \
    --format="get(address)")

echo "IP Reservada: $IP_ADDRESS"

# Asignar a la instancia (requiere detener/iniciar)
gcloud compute instances delete-access-config iot-tunnel-server \
    --zone=us-central1-a \
    --access-config-name="External NAT"

gcloud compute instances add-access-config iot-tunnel-server \
    --zone=us-central1-a \
    --access-config-name="External NAT" \
    --address=$IP_ADDRESS
```

## Paso 4: Conectar y Configurar

```bash
# Conectar vía SSH
gcloud compute ssh iot-tunnel-server --zone=us-central1-a

# O usando SSH directo
ssh -i ~/.ssh/google_compute_engine user@$IP_ADDRESS

# Configurar según DEPLOYMENT.md
# ...
```

## Paso 5: Configuraciones Adicionales

### Cloud Monitoring

```bash
# Instalar agente de monitoring
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install

# Configurar alertas
gcloud alpha monitoring policies create \
    --notification-channels=CHANNEL_ID \
    --display-name="High CPU Alert" \
    --condition-display-name="CPU > 80%" \
    --condition-threshold-value=0.8 \
    --condition-threshold-duration=300s
```

### Automated Backups

```bash
# Crear snapshot schedule
gcloud compute resource-policies create snapshot-schedule iot-tunnel-backup \
    --max-retention-days=30 \
    --on-source-disk-delete=keep-auto-snapshots \
    --daily-schedule \
    --start-time=02:00 \
    --storage-location=us-central1 \
    --region=us-central1

# Asociar a disco
DISK_NAME=$(gcloud compute instances describe iot-tunnel-server \
    --zone=us-central1-a \
    --format="get(disks[0].source.basename())")

gcloud compute disks add-resource-policies $DISK_NAME \
    --resource-policies=iot-tunnel-backup \
    --zone=us-central1-a
```

### Cloud Armor (DDoS Protection)

```bash
# Crear política de seguridad
gcloud compute security-policies create iot-tunnel-policy \
    --description="DDoS protection for IoT tunnel server"

# Agregar regla de rate limiting
gcloud compute security-policies rules create 1000 \
    --security-policy=iot-tunnel-policy \
    --expression="true" \
    --action=rate-based-ban \
    --rate-limit-threshold-count=100 \
    --rate-limit-threshold-interval-sec=60 \
    --ban-duration-sec=600
```

### VPC Service Controls (Opcional)

```bash
# Para mayor seguridad en proyectos sensibles
gcloud access-context-manager perimeters create iot_perimeter \
    --title="IoT Tunnel Perimeter" \
    --resources=projects/PROJECT_NUMBER \
    --restricted-services=compute.googleapis.com
```

## Optimización de Costos

### Committed Use Discounts

```bash
# Comprar commitment de 1 año para e2-small
gcloud compute commitments create iot-tunnel-commitment \
    --plan=12-month \
    --resources=vcpu=2,memory=2GB \
    --region=us-central1
```

### Rightsizing Recommendations

```bash
# Ver recomendaciones de rightsizing
gcloud compute instances list \
    --format="table(name,zone,machineType,status)" \
    --filter="name:iot-tunnel-server"

# Cambiar tipo de máquina si es necesario
gcloud compute instances set-machine-type iot-tunnel-server \
    --machine-type=e2-micro \
    --zone=us-central1-a
```

### Preemptible VMs (solo dev/test)

```bash
gcloud compute instances create iot-tunnel-server-preemptible \
    --zone=us-central1-a \
    --machine-type=e2-small \
    --preemptible \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud
```

## Estimación de Costos Mensual

Para región us-central1:

| Componente | Costo Mensual |
|------------|---------------|
| e2-small (on-demand) | ~$13 |
| e2-small (1-year commitment) | ~$8 |
| Persistent Disk 20 GB | ~$2 |
| Static IP | ~$0 (si está en uso) |
| Egress 100 GB | ~$12 |
| **Total** | **~$22-35** |

## Terraform Configuration

```hcl
# main.tf
provider "google" {
  project = "your-project-id"
  region  = "us-central1"
  zone    = "us-central1-a"
}

resource "google_compute_instance" "iot_tunnel" {
  name         = "iot-tunnel-server"
  machine_type = "e2-small"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    network = "default"

    access_config {
      nat_ip = google_compute_address.iot_tunnel.address
    }
  }

  tags = ["ssh-server"]

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y git
    # Additional setup commands
  EOF
}

resource "google_compute_address" "iot_tunnel" {
  name   = "iot-tunnel-ip"
  region = "us-central1"
}

resource "google_compute_firewall" "ssh" {
  name    = "allow-ssh-iot-tunnel"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh-server"]
}

output "instance_ip" {
  value = google_compute_address.iot_tunnel.address
}
```

Deploy:
```bash
terraform init
terraform plan
terraform apply
```

## Security Best Practices en GCP

### IAM Roles

```bash
# Crear service account dedicada
gcloud iam service-accounts create iot-tunnel-sa \
    --display-name="IoT Tunnel Service Account"

# Asignar rol mínimo necesario
gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:iot-tunnel-sa@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/compute.instanceAdmin.v1"
```

### OS Login

```bash
# Habilitar OS Login para mejor seguridad
gcloud compute instances add-metadata iot-tunnel-server \
    --zone=us-central1-a \
    --metadata enable-oslogin=TRUE
```

### Shielded VM

```bash
# Crear instancia con Shielded VM habilitado
gcloud compute instances create iot-tunnel-server \
    --zone=us-central1-a \
    --machine-type=e2-small \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring
```

## Checklist de Deployment

- [ ] Instancia de Compute Engine creada
- [ ] Firewall rules configuradas
- [ ] IP estática reservada y asignada
- [ ] Servidor configurado según DEPLOYMENT.md
- [ ] Cloud Monitoring habilitado
- [ ] Backups automáticos configurados
- [ ] Costos optimizados
- [ ] Security best practices implementadas

## Referencias

- [Compute Engine Documentation](https://cloud.google.com/compute/docs)
- [VPC Firewall Rules](https://cloud.google.com/vpc/docs/firewalls)
- [GCP Pricing Calculator](https://cloud.google.com/products/calculator)
