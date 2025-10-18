# Configuración de Azure para Túneles SSH IoT

## Visión General

Esta guía cubre la configuración de una VM en Azure como servidor de túneles SSH inversos para dispositivos IoT.

## Requisitos

- Cuenta de Azure activa
- Azure CLI instalado (opcional)
- Acceso a Azure Portal

## Paso 1: Crear Máquina Virtual

### Desde Azure Portal

1. Ir a **Virtual Machines** > **Create**
2. Configuración básica:
   - **Resource Group**: iot-tunnel-rg (crear nuevo)
   - **VM Name**: iot-tunnel-server
   - **Region**: Seleccionar región cercana
   - **Image**: Ubuntu Server 22.04 LTS
   - **Size**: Standard_B2s (2 vCPU, 4 GiB RAM)
   - **Authentication**: SSH public key
   - **Username**: azureuser

### Desde Azure CLI

```bash
# Crear resource group
az group create --name iot-tunnel-rg --location eastus

# Crear VM
az vm create \
    --resource-group iot-tunnel-rg \
    --name iot-tunnel-server \
    --image UbuntuLTS \
    --size Standard_B2s \
    --admin-username azureuser \
    --generate-ssh-keys \
    --public-ip-sku Standard
```

## Paso 2: Configurar Network Security Group (NSG)

### Desde Portal

1. Ir a **Virtual Machines** > **iot-tunnel-server** > **Networking**
2. Click en **Add inbound port rule**
3. Configurar regla SSH:
   - **Source**: Any (o restringir a IPs específicas)
   - **Source port ranges**: *
   - **Destination**: Any
   - **Destination port ranges**: 22
   - **Protocol**: TCP
   - **Action**: Allow
   - **Priority**: 1000
   - **Name**: AllowSSH

### Desde Azure CLI

```bash
# Crear NSG
az network nsg create \
    --resource-group iot-tunnel-rg \
    --name iot-tunnel-nsg

# Agregar regla SSH
az network nsg rule create \
    --resource-group iot-tunnel-rg \
    --nsg-name iot-tunnel-nsg \
    --name AllowSSH \
    --priority 1000 \
    --source-address-prefixes '*' \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 22 \
    --access Allow \
    --protocol Tcp \
    --direction Inbound

# Asociar NSG a la VM
az network nic update \
    --resource-group iot-tunnel-rg \
    --name iot-tunnel-serverVMNic \
    --network-security-group iot-tunnel-nsg
```

## Paso 3: Configurar IP Pública Estática

### Desde Portal

1. Ir a **Public IP addresses**
2. Seleccionar la IP de iot-tunnel-server
3. En **Configuration**:
   - **Assignment**: Static
   - **DNS name label**: iot-tunnel-server (opcional)

### Desde Azure CLI

```bash
# Obtener nombre de la IP pública
PUBLIC_IP_NAME=$(az network public-ip list \
    --resource-group iot-tunnel-rg \
    --query "[?contains(name, 'iot-tunnel-server')].name" \
    --output tsv)

# Configurar como estática
az network public-ip update \
    --resource-group iot-tunnel-rg \
    --name $PUBLIC_IP_NAME \
    --allocation-method Static

# Configurar DNS label
az network public-ip update \
    --resource-group iot-tunnel-rg \
    --name $PUBLIC_IP_NAME \
    --dns-name iot-tunnel-server

# Obtener dirección IP
az network public-ip show \
    --resource-group iot-tunnel-rg \
    --name $PUBLIC_IP_NAME \
    --query ipAddress \
    --output tsv
```

## Paso 4: Conectar y Configurar Servidor

```bash
# Conectar a la VM
ssh azureuser@<PUBLIC_IP>

# Actualizar sistema
sudo apt-get update
sudo apt-get upgrade -y

# Clonar repositorio
cd /opt
sudo git clone https://github.com/your-org/iot-ssh-reverse-tunnel.git
cd iot-ssh-reverse-tunnel

# Ejecutar configuración según DEPLOYMENT.md
# ...
```

## Paso 5: Configuraciones Adicionales de Seguridad

### Habilitar Azure Firewall (Opcional, para deployments grandes)

```bash
# Crear Azure Firewall
az network firewall create \
    --resource-group iot-tunnel-rg \
    --name iot-tunnel-firewall \
    --location eastus

# Crear subnet para firewall
az network vnet subnet create \
    --resource-group iot-tunnel-rg \
    --vnet-name iot-tunnel-vnet \
    --name AzureFirewallSubnet \
    --address-prefixes 10.0.1.0/26

# Configurar reglas de firewall
# ...
```

### Habilitar Azure DDoS Protection

```bash
# Crear plan de protección DDoS
az network ddos-protection create \
    --resource-group iot-tunnel-rg \
    --name iot-tunnel-ddos \
    --location eastus

# Asociar a VNet
az network vnet update \
    --resource-group iot-tunnel-rg \
    --name iot-tunnel-vnet \
    --ddos-protection-plan iot-tunnel-ddos
```

## Paso 6: Monitoreo con Azure Monitor

### Habilitar diagnósticos

```bash
# Crear Log Analytics Workspace
az monitor log-analytics workspace create \
    --resource-group iot-tunnel-rg \
    --workspace-name iot-tunnel-logs

# Habilitar diagnósticos para VM
az monitor diagnostic-settings create \
    --resource iot-tunnel-server \
    --resource-group iot-tunnel-rg \
    --name vm-diagnostics \
    --workspace iot-tunnel-logs \
    --logs '[{"category": "Administrative","enabled": true}]'
```

### Configurar alertas

```bash
# Alerta de alto uso de CPU
az monitor metrics alert create \
    --name high-cpu \
    --resource-group iot-tunnel-rg \
    --scopes $(az vm show -g iot-tunnel-rg -n iot-tunnel-server --query id -o tsv) \
    --condition "avg Percentage CPU > 80" \
    --description "Alert when CPU exceeds 80%"
```

## Paso 7: Backup y Recovery

```bash
# Habilitar Azure Backup
az backup vault create \
    --resource-group iot-tunnel-rg \
    --name iot-tunnel-vault \
    --location eastus

# Configurar política de backup
az backup policy create \
    --resource-group iot-tunnel-rg \
    --vault-name iot-tunnel-vault \
    --name daily-backup \
    --backup-management-type AzureIaasVM \
    --policy '{"schedulePolicy":{"schedulePolicyType":"SimpleSchedulePolicy","scheduleRunFrequency":"Daily","scheduleRunTimes":["2024-01-01T02:00:00Z"]},"retentionPolicy":{"retentionPolicyType":"LongTermRetentionPolicy","dailySchedule":{"retentionDuration":{"count":30,"durationType":"Days"}}}}'

# Habilitar backup para VM
az backup protection enable-for-vm \
    --resource-group iot-tunnel-rg \
    --vault-name iot-tunnel-vault \
    --vm iot-tunnel-server \
    --policy-name daily-backup
```

## Optimización de Costos

### Usar Reserved Instances

Para reducir costos en deployments de largo plazo:

1. Ir a **Reservations** en Azure Portal
2. Comprar reservación de 1 o 3 años para el tamaño de VM
3. Ahorro: hasta 72% comparado con pay-as-you-go

### Auto-shutdown

```bash
# Configurar auto-shutdown a las 10 PM
az vm auto-shutdown \
    --resource-group iot-tunnel-rg \
    --name iot-tunnel-server \
    --time 2200
```

### Usar Azure Spot VMs (solo para dev/test)

```bash
az vm create \
    --resource-group iot-tunnel-rg \
    --name iot-tunnel-server-spot \
    --image UbuntuLTS \
    --size Standard_B2s \
    --priority Spot \
    --max-price -1 \
    --eviction-policy Deallocate
```

## Estimación de Costos Mensual

Para región East US (aproximado):

| Componente | Costo Mensual |
|------------|---------------|
| VM Standard_B2s (pay-as-you-go) | ~$30 |
| VM Standard_B2s (1-year reserved) | ~$15 |
| Public IP estática | ~$3 |
| Storage (128 GB SSD) | ~$10 |
| Bandwidth (100 GB egress) | ~$9 |
| **Total** | **~$37-67** |

## Checklist de Deployment

- [ ] VM creada con tamaño adecuado
- [ ] NSG configurado con reglas SSH
- [ ] IP pública estática asignada
- [ ] DNS configurado (opcional)
- [ ] Servidor configurado según DEPLOYMENT.md
- [ ] Monitoreo habilitado
- [ ] Alertas configuradas
- [ ] Backup habilitado
- [ ] Costos optimizados

## Referencias

- [Azure Virtual Machines Documentation](https://docs.microsoft.com/en-us/azure/virtual-machines/)
- [Azure Network Security Groups](https://docs.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
- [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
