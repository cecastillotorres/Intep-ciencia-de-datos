#!/bin/bash
# ============================================================================
# Script de despliegue automatizado para Apache Flink en Azure HDInsight
# ============================================================================
# Este script automatiza todo el proceso de despliegue y configuración
# ============================================================================

set -e  # Salir si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funciones auxiliares
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# ============================================================================
# Verificar prerrequisitos
# ============================================================================

print_header "Verificando prerrequisitos"

# Verificar Azure CLI
if ! command -v az &> /dev/null; then
    print_error "Azure CLI no está instalado"
    echo "Instala desde: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi
print_success "Azure CLI instalado"

# Verificar Terraform
if ! command -v terraform &> /dev/null; then
    print_error "Terraform no está instalado"
    echo "Instala desde: https://www.terraform.io/downloads"
    exit 1
fi
print_success "Terraform instalado"

# Verificar login en Azure
if ! az account show &> /dev/null; then
    print_error "No estás autenticado en Azure"
    echo "Ejecuta: az login"
    exit 1
fi
print_success "Autenticado en Azure"

# Mostrar suscripción activa
SUBSCRIPTION=$(az account show --query name -o tsv)
print_info "Suscripción activa: $SUBSCRIPTION"

# ============================================================================
# Configuración
# ============================================================================

print_header "Configuración del proyecto"

# Directorio de Terraform
TERRAFORM_DIR="terraform"

# Verificar que terraform.tfvars existe
if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
    print_warning "No se encontró terraform.tfvars"
    
    read -p "¿Deseas crear uno ahora? (s/n): " CREATE_TFVARS
    
    if [ "$CREATE_TFVARS" = "s" ] || [ "$CREATE_TFVARS" = "S" ]; then
        print_info "Creando terraform.tfvars desde el ejemplo..."
        cp "$TERRAFORM_DIR/terraform.tfvars.example" "$TERRAFORM_DIR/terraform.tfvars"
        
        print_warning "IMPORTANTE: Edita $TERRAFORM_DIR/terraform.tfvars con tus valores"
        read -p "Presiona Enter cuando hayas terminado de editarlo..."
    else
        print_error "No se puede continuar sin terraform.tfvars"
        exit 1
    fi
fi

print_success "Archivo terraform.tfvars encontrado"

# ============================================================================
# Desplegar infraestructura con Terraform
# ============================================================================

print_header "Desplegando infraestructura con Terraform"

cd "$TERRAFORM_DIR"

# Inicializar Terraform
print_info "Inicializando Terraform..."
terraform init

# Validar configuración
print_info "Validando configuración..."
terraform validate

# Mostrar plan
print_info "Generando plan de ejecución..."
terraform plan -out=tfplan

# Confirmar despliegue
echo ""
read -p "¿Deseas aplicar este plan? (s/n): " APPLY_TERRAFORM

if [ "$APPLY_TERRAFORM" != "s" ] && [ "$APPLY_TERRAFORM" != "S" ]; then
    print_warning "Despliegue cancelado por el usuario"
    exit 0
fi

# Aplicar
print_info "Aplicando configuración (esto tomará ~15-20 minutos)..."
terraform apply tfplan

# Guardar outputs
print_info "Guardando outputs de Terraform..."
terraform output -json > ../terraform_outputs.json

# Extraer valores importantes
CLUSTER_NAME=$(terraform output -raw cluster_name)
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
SSH_COMMAND=$(terraform output -raw ssh_command)

cd ..

print_success "Infraestructura desplegada exitosamente"

# ============================================================================
# Obtener Storage Key
# ============================================================================

print_header "Configurando acceso a Storage"

print_info "Obteniendo Storage Account Key..."
STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" -o tsv)

# Guardar en archivo de configuración
cat > .env <<EOF
# Configuración generada automáticamente
AZURE_STORAGE_ACCOUNT=$STORAGE_ACCOUNT
AZURE_STORAGE_KEY=$STORAGE_KEY
CLUSTER_NAME=$CLUSTER_NAME
RESOURCE_GROUP=$RESOURCE_GROUP
EOF

print_success "Credenciales guardadas en .env"

# ============================================================================
# Subir código a Storage
# ============================================================================

print_header "Subiendo código a Azure Storage"

print_info "Subiendo script de streaming..."
az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name scripts \
    --name flink_streaming.py \
    --file flink_streaming_hdinsight.py \
    --overwrite

print_info "Subiendo requirements.txt..."
az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name scripts \
    --name requirements.txt \
    --file requirements.txt \
    --overwrite

print_success "Código subido exitosamente"

# ============================================================================
# Instrucciones de configuración del cluster
# ============================================================================

print_header "Configuración del cluster HDInsight"

print_info "Esperando a que el cluster esté completamente disponible..."
echo "Esto puede tomar algunos minutos adicionales..."
sleep 60

print_success "Cluster listo para configuración"

# Crear script de setup remoto
cat > setup_flink_remote.sh <<'EOF'
#!/bin/bash
set -e

echo "Instalando Apache Flink..."

# Descargar Flink
FLINK_VERSION="1.17.2"
cd /tmp
wget -q https://archive.apache.org/dist/flink/flink-${FLINK_VERSION}/flink-${FLINK_VERSION}-bin-scala_2.12.tgz
tar -xzf flink-${FLINK_VERSION}-bin-scala_2.12.tgz
sudo mv flink-${FLINK_VERSION} /opt/flink
sudo chown -R $USER:$USER /opt/flink

# Configurar variables de entorno
echo 'export FLINK_HOME=/opt/flink' >> ~/.bashrc
echo 'export PATH=$PATH:$FLINK_HOME/bin' >> ~/.bashrc
source ~/.bashrc

# Instalar Python y dependencias
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv

# Crear entorno virtual
python3 -m venv ~/flink-env
source ~/flink-env/bin/activate

# Instalar PyFlink
pip install apache-flink pandas azure-storage-file-datalake

echo "✓ Apache Flink instalado y configurado correctamente"
EOF

# Subir script de setup al cluster
print_info "Subiendo script de configuración al cluster..."
scp -o StrictHostKeyChecking=no setup_flink_remote.sh "${SSH_COMMAND#ssh }":~/

# Ejecutar script de setup
print_info "Ejecutando script de configuración en el cluster..."
ssh -o StrictHostKeyChecking=no "${SSH_COMMAND#ssh }" "bash ~/setup_flink_remote.sh"

print_success "Flink configurado en el cluster"

# ============================================================================
# Iniciar Flink
# ============================================================================

print_header "Iniciando Apache Flink"

print_info "Iniciando cluster de Flink..."
ssh -o StrictHostKeyChecking=no "${SSH_COMMAND#ssh }" "/opt/flink/bin/start-cluster.sh"

print_success "Cluster de Flink iniciado"

# ============================================================================
# Resumen final
# ============================================================================

print_header "🎉 Despliegue completado exitosamente"

echo ""
echo "📋 Información del cluster:"
echo "  • Resource Group: $RESOURCE_GROUP"
echo "  • Cluster Name: $CLUSTER_NAME"
echo "  • Storage Account: $STORAGE_ACCOUNT"
echo ""
echo "🔗 Conexiones:"
echo "  • SSH: $SSH_COMMAND"
echo "  • Ambari Web UI: https://${CLUSTER_NAME}.azurehdinsight.net"
echo "  • Flink Web UI: Crear túnel SSH con: ssh -L 8081:localhost:8081 ${SSH_COMMAND#ssh }"
echo ""
echo "📝 Próximos pasos:"
echo "  1. Conectarse al cluster:"
echo "     $SSH_COMMAND"
echo ""
echo "  2. Activar entorno virtual:"
echo "     source ~/flink-env/bin/activate"
echo ""
echo "  3. Configurar variables de entorno:"
echo "     export AZURE_STORAGE_ACCOUNT=$STORAGE_ACCOUNT"
echo "     export AZURE_STORAGE_KEY=TU_STORAGE_KEY"
echo ""
echo "  4. Descargar y ejecutar el script:"
echo "     az storage blob download --account-name $STORAGE_ACCOUNT --container-name scripts --name flink_streaming.py --file flink_streaming.py"
echo "     python flink_streaming.py"
echo ""
echo "💰 Costos estimados:"
echo "  • ~$0.48/hora (~$350/mes) con la configuración actual"
echo "  • Para detener el cluster: az hdinsight stop --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP"
echo "  • Para eliminar todo: cd terraform && terraform destroy"
echo ""
print_success "¡Todo listo para usar Apache Flink en Azure!"

# Guardar resumen en archivo
cat > DEPLOYMENT_SUMMARY.txt <<EOF
========================================
Resumen de Despliegue - Apache Flink
========================================
Fecha: $(date)

RECURSOS CREADOS:
  - Resource Group: $RESOURCE_GROUP
  - Cluster HDInsight: $CLUSTER_NAME
  - Storage Account: $STORAGE_ACCOUNT

CONEXIONES:
  - SSH: $SSH_COMMAND
  - Ambari: https://${CLUSTER_NAME}.azurehdinsight.net
  - Flink UI: ssh -L 8081:localhost:8081 ${SSH_COMMAND#ssh }

CREDENCIALES:
  - Almacenadas en: .env
  - Storage Key: Ver archivo .env

ARCHIVOS IMPORTANTES:
  - terraform_outputs.json: Outputs de Terraform
  - .env: Variables de entorno
  - DEPLOY_GUIDE.md: Guía completa de despliegue

COSTOS:
  - Estimado: ~$0.48/hora (~$350/mes)
  
COMANDOS ÚTILES:
  - Detener cluster: az hdinsight stop --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP
  - Iniciar cluster: az hdinsight start --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP
  - Eliminar todo: cd terraform && terraform destroy

========================================
EOF

print_success "Resumen guardado en DEPLOYMENT_SUMMARY.txt"
