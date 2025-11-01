# ============================================================================
# Terraform Configuration for Azure HDInsight with Apache Flink
# ============================================================================
# Este script crea la infraestructura necesaria para ejecutar Apache Flink
# en Azure HDInsight, incluyendo:
# - Resource Group
# - Storage Account (ADLS Gen2)
# - Virtual Network
# - HDInsight Cluster con Flink
# ============================================================================

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# ============================================================================
# Variables
# ============================================================================

variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "intep-flink"
}

variable "environment" {
  description = "Ambiente (dev, prod)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Región de Azure"
  type        = string
  default     = "East US"
}

variable "admin_username" {
  description = "Usuario administrador del cluster"
  type        = string
  default     = "adminuser"
}

variable "admin_password" {
  description = "Contraseña del administrador (min 10 caracteres, mayúsculas, minúsculas, números y símbolos)"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Llave pública SSH para acceso al cluster"
  type        = string
}

variable "cluster_tier" {
  description = "Tier del cluster (Standard o Premium)"
  type        = string
  default     = "Standard"
}

variable "head_node_vm_size" {
  description = "Tamaño de VM para nodos head"
  type        = string
  default     = "Standard_D3_v2"
}

variable "worker_node_vm_size" {
  description = "Tamaño de VM para nodos worker"
  type        = string
  default     = "Standard_D3_v2"
}

variable "worker_node_count" {
  description = "Número de nodos worker"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags para los recursos"
  type        = map(string)
  default = {
    Project     = "INTEP Ciencia de Datos"
    Environment = "Development"
    ManagedBy   = "Terraform"
    Purpose     = "Apache Flink Streaming"
  }
}

# ============================================================================
# Locals
# ============================================================================

locals {
  resource_suffix = "${var.project_name}-${var.environment}"
  
  # Nombres de recursos
  resource_group_name  = "rg-${local.resource_suffix}"
  storage_account_name = lower(replace("st${var.project_name}${var.environment}${random_string.suffix.result}", "-", ""))
  vnet_name           = "vnet-${local.resource_suffix}"
  subnet_name         = "snet-${local.resource_suffix}"
  nsg_name            = "nsg-${local.resource_suffix}"
  cluster_name        = "hdi-${local.resource_suffix}"
  
  # Nombres de contenedores
  container_name      = "flink-data"
  scripts_container   = "scripts"
  logs_container      = "logs"
}

# ============================================================================
# Random Resources
# ============================================================================

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ============================================================================
# Resource Group
# ============================================================================

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# ============================================================================
# Storage Account (ADLS Gen2)
# ============================================================================

resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true  # Habilita Data Lake Storage Gen2
  
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
  
  tags = var.tags
}

# Contenedor para datos de Flink
resource "azurerm_storage_container" "flink_data" {
  name                  = local.container_name
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Contenedor para scripts
resource "azurerm_storage_container" "scripts" {
  name                  = local.scripts_container
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Contenedor para logs
resource "azurerm_storage_container" "logs" {
  name                  = local.logs_container
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ============================================================================
# Virtual Network
# ============================================================================

resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_subnet" "main" {
  name                 = local.subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = local.nsg_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Regla para SSH
  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # Regla para Flink Web UI
  security_rule {
    name                       = "AllowFlinkUI"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8081"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # Regla para Ambari
  security_rule {
    name                       = "AllowAmbari"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# ============================================================================
# HDInsight Cluster con Apache Flink
# ============================================================================

resource "azurerm_hdinsight_kafka_cluster" "main" {
  name                = local.cluster_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  cluster_version     = "4.0"
  tier                = var.cluster_tier
  
  component_version {
    kafka = "2.4"
  }
  
  gateway {
    username = var.admin_username
    password = var.admin_password
  }
  
  storage_account {
    storage_container_id = azurerm_storage_container.flink_data.id
    storage_account_key  = azurerm_storage_account.main.primary_access_key
    is_default           = true
  }
  
  roles {
    head_node {
      vm_size  = var.head_node_vm_size
      username = var.admin_username
      password = var.admin_password
      
      ssh_keys = [var.ssh_public_key]
      
      subnet_id            = azurerm_subnet.main.id
      virtual_network_id   = azurerm_virtual_network.main.id
    }
    
    worker_node {
      vm_size               = var.worker_node_vm_size
      username              = var.admin_username
      password              = var.admin_password
      number_of_disks_per_node = 2
      target_instance_count = var.worker_node_count
      
      ssh_keys = [var.ssh_public_key]
      
      subnet_id            = azurerm_subnet.main.id
      virtual_network_id   = azurerm_virtual_network.main.id
    }
    
    zookeeper_node {
      vm_size  = "Standard_D3_v2"
      username = var.admin_username
      password = var.admin_password
      
      ssh_keys = [var.ssh_public_key]
      
      subnet_id            = azurerm_subnet.main.id
      virtual_network_id   = azurerm_virtual_network.main.id
    }
  }
  
  tags = var.tags
  
  depends_on = [
    azurerm_subnet_network_security_group_association.main
  ]
}

# ============================================================================
# Script de inicialización para Flink
# ============================================================================

resource "azurerm_storage_blob" "flink_setup_script" {
  name                   = "setup-flink.sh"
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source_content         = <<-EOT
#!/bin/bash
# Script de configuración para Apache Flink en HDInsight

set -e

echo "Instalando Apache Flink..."

# Descargar e instalar Flink
FLINK_VERSION="1.17.2"
SCALA_VERSION="2.12"
FLINK_HOME="/opt/flink"

cd /tmp
wget -q https://archive.apache.org/dist/flink/flink-$${FLINK_VERSION}/flink-$${FLINK_VERSION}-bin-scala_$${SCALA_VERSION}.tgz
tar -xzf flink-$${FLINK_VERSION}-bin-scala_$${SCALA_VERSION}.tgz
sudo mv flink-$${FLINK_VERSION} $${FLINK_HOME}
sudo chown -R $USER:$USER $${FLINK_HOME}

# Configurar variables de entorno
echo "export FLINK_HOME=$${FLINK_HOME}" >> ~/.bashrc
echo "export PATH=\$PATH:\$FLINK_HOME/bin" >> ~/.bashrc
source ~/.bashrc

# Instalar Python y PyFlink
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv
pip3 install apache-flink pandas

# Configurar Flink para Azure Storage
cat > $${FLINK_HOME}/conf/flink-conf.yaml <<EOF
# Flink Configuration
jobmanager.rpc.address: localhost
jobmanager.rpc.port: 6123
jobmanager.memory.process.size: 1600m
taskmanager.memory.process.size: 1728m
taskmanager.numberOfTaskSlots: 2
parallelism.default: 2

# Azure Storage Configuration
fs.azure.account.key.${azurerm_storage_account.main.name}.dfs.core.windows.net: ${azurerm_storage_account.main.primary_access_key}
EOF

# Iniciar Flink cluster
$${FLINK_HOME}/bin/start-cluster.sh

echo "Apache Flink instalado y configurado correctamente"
echo "Flink Web UI disponible en: http://localhost:8081"
  EOT
}

# ============================================================================
# Outputs
# ============================================================================

output "resource_group_name" {
  description = "Nombre del Resource Group"
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "Nombre de la Storage Account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_key" {
  description = "Key de la Storage Account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_connection_string" {
  description = "Connection string de la Storage Account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "cluster_name" {
  description = "Nombre del cluster HDInsight"
  value       = azurerm_hdinsight_kafka_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint del cluster HDInsight"
  value       = "https://${azurerm_hdinsight_kafka_cluster.main.name}.azurehdinsight.net"
}

output "ambari_web_url" {
  description = "URL de Ambari Web UI"
  value       = "https://${azurerm_hdinsight_kafka_cluster.main.name}.azurehdinsight.net"
}

output "ssh_command" {
  description = "Comando SSH para conectarse al cluster"
  value       = "ssh ${var.admin_username}@${azurerm_hdinsight_kafka_cluster.main.name}-ssh.azurehdinsight.net"
}

output "flink_data_container" {
  description = "URL del contenedor de datos de Flink"
  value       = "abfss://${local.container_name}@${azurerm_storage_account.main.name}.dfs.core.windows.net/"
}

output "setup_instructions" {
  description = "Instrucciones de configuración"
  value       = <<-EOT
    Infraestructura creada exitosamente!
    
    Recursos creados:
    - Resource Group: ${azurerm_resource_group.main.name}
    - Storage Account: ${azurerm_storage_account.main.name}
    - HDInsight Cluster: ${azurerm_hdinsight_kafka_cluster.main.name}
    
    Conexiones:
    - Ambari Web UI: https://${azurerm_hdinsight_kafka_cluster.main.name}.azurehdinsight.net
    - SSH: ssh ${var.admin_username}@${azurerm_hdinsight_kafka_cluster.main.name}-ssh.azurehdinsight.net
    
    Próximos pasos:
    1. Conéctate al cluster vía SSH
    2. Ejecuta el script de setup: bash /mnt/scripts/setup-flink.sh
    3. Verifica Flink: http://localhost:8081 (usa SSH tunneling)
    4. Sube tu código Python al storage account
    5. Ejecuta: flink run -py tu_script.py
  EOT
}
