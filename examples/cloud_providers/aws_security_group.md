# Configuración de AWS para Túneles SSH IoT

## Resumen

Guía para configurar una instancia EC2 en AWS como servidor de túneles SSH inversos.

## Paso 1: Crear Instancia EC2

### Desde AWS Console

1. Navegar a **EC2** > **Launch Instance**
2. Configuración:
   - **Name**: iot-tunnel-server
   - **AMI**: Ubuntu Server 22.04 LTS
   - **Instance type**: t3.small (2 vCPU, 2 GiB RAM)
   - **Key pair**: Crear o seleccionar existing
   - **Network**: VPC default o custom
   - **Storage**: 20 GB gp3

### Desde AWS CLI

```bash
# Crear key pair
aws ec2 create-key-pair \
    --key-name iot-tunnel-key \
    --query 'KeyMaterial' \
    --output text > iot-tunnel-key.pem
chmod 400 iot-tunnel-key.pem

# Lanzar instancia
aws ec2 run-instances \
    --image-id ami-0c7217cdde317cfec \
    --instance-type t3.small \
    --key-name iot-tunnel-key \
    --security-group-ids sg-xxxxxx \
    --subnet-id subnet-xxxxxx \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=iot-tunnel-server}]'
```

## Paso 2: Configurar Security Group

### Desde Console

1. Ir a **EC2** > **Security Groups** > **Create security group**
2. Configuración:
   - **Name**: iot-tunnel-sg
   - **Description**: Security group for IoT SSH tunnels
   - **VPC**: Seleccionar VPC

3. Inbound rules:
   - **Type**: SSH
   - **Protocol**: TCP
   - **Port**: 22
   - **Source**: 0.0.0.0/0 (o restringir)

### Desde AWS CLI

```bash
# Crear security group
SG_ID=$(aws ec2 create-security-group \
    --group-name iot-tunnel-sg \
    --description "Security group for IoT SSH tunnels" \
    --query 'GroupId' \
    --output text)

# Agregar regla SSH
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# Asociar a instancia
aws ec2 modify-instance-attribute \
    --instance-id i-xxxxxxxxx \
    --groups $SG_ID
```

## Paso 3: Elastic IP (IP Estática)

```bash
# Allocar Elastic IP
ALLOC_ID=$(aws ec2 allocate-address \
    --domain vpc \
    --query 'AllocationId' \
    --output text)

# Asociar a instancia
aws ec2 associate-address \
    --instance-id i-xxxxxxxxx \
    --allocation-id $ALLOC_ID

# Obtener IP pública
aws ec2 describe-addresses \
    --allocation-ids $ALLOC_ID \
    --query 'Addresses[0].PublicIp' \
    --output text
```

## Paso 4: Conectar y Configurar

```bash
# Conectar a instancia
ssh -i iot-tunnel-key.pem ubuntu@<PUBLIC_IP>

# Configurar según DEPLOYMENT.md
# ...
```

## Paso 5: Configuraciones Adicionales

### CloudWatch Monitoring

```bash
# Habilitar detailed monitoring
aws ec2 monitor-instances --instance-ids i-xxxxxxxxx

# Crear alarma de CPU
aws cloudwatch put-metric-alarm \
    --alarm-name high-cpu-iot-tunnel \
    --alarm-description "Alert when CPU > 80%" \
    --metric-name CPUUtilization \
    --namespace AWS/EC2 \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=InstanceId,Value=i-xxxxxxxxx \
    --evaluation-periods 2
```

### AWS Backup

```bash
# Crear plan de backup
aws backup create-backup-plan \
    --backup-plan "{\"BackupPlanName\":\"iot-tunnel-backup\",\"Rules\":[{\"RuleName\":\"daily\",\"TargetBackupVaultName\":\"Default\",\"ScheduleExpression\":\"cron(0 2 * * ? *)\",\"Lifecycle\":{\"DeleteAfterDays\":30}}]}"

# Asociar recurso
aws backup create-backup-selection \
    --backup-plan-id <plan-id> \
    --backup-selection "{\"SelectionName\":\"iot-tunnel-selection\",\"IamRoleArn\":\"arn:aws:iam::account:role/service-role/AWSBackupDefaultServiceRole\",\"Resources\":[\"arn:aws:ec2:region:account:instance/i-xxxxxxxxx\"]}"
```

### EBS Optimization

```bash
# Modificar volumen a gp3 (mejor performance/costo)
VOLUME_ID=$(aws ec2 describe-instances \
    --instance-ids i-xxxxxxxxx \
    --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
    --output text)

aws ec2 modify-volume \
    --volume-id $VOLUME_ID \
    --volume-type gp3 \
    --iops 3000 \
    --throughput 125
```

## Optimización de Costos

### Reserved Instances

```bash
# Comprar RI de 1 año
aws ec2 purchase-reserved-instances-offering \
    --reserved-instances-offering-id xxxxxxxx \
    --instance-count 1
```

### Savings Plans

- Ir a AWS Cost Management > Savings Plans
- Seleccionar Compute Savings Plans
- Commitment: $10-20/month para t3.small

### Spot Instances (solo dev/test)

```bash
aws ec2 request-spot-instances \
    --spot-price "0.01" \
    --instance-count 1 \
    --type "persistent" \
    --launch-specification "{...}"
```

## Estimación de Costos Mensual

Para región us-east-1:

| Componente | Costo Mensual |
|------------|---------------|
| t3.small (on-demand) | ~$15 |
| t3.small (1-year RI) | ~$9 |
| EBS 20 GB gp3 | ~$2 |
| Elastic IP | ~$0 (si está asociado) |
| Data transfer (100 GB) | ~$9 |
| **Total** | **~$20-35** |

## Terraform Configuration (Opcional)

```hcl
# main.tf
provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "iot_tunnel" {
  ami           = "ami-0c7217cdde317cfec"
  instance_type = "t3.small"
  key_name      = "iot-tunnel-key"

  vpc_security_group_ids = [aws_security_group.iot_tunnel.id]

  tags = {
    Name = "iot-tunnel-server"
  }
}

resource "aws_security_group" "iot_tunnel" {
  name        = "iot-tunnel-sg"
  description = "Security group for IoT SSH tunnels"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eip" "iot_tunnel" {
  instance = aws_instance.iot_tunnel.id
  domain   = "vpc"
}

output "public_ip" {
  value = aws_eip.iot_tunnel.public_ip
}
```

Deploy:
```bash
terraform init
terraform plan
terraform apply
```

## Referencias

- [EC2 User Guide](https://docs.aws.amazon.com/ec2/)
- [AWS Security Groups](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)
- [AWS Pricing Calculator](https://calculator.aws/)
