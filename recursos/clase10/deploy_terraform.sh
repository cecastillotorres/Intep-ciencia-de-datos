#!/bin/bash
# ============================================================================
# Script de despliegue automatizado - Apache Flink en Azure HDInsight
# ============================================================================
# Este script ejecuta el despliegue completo de la infraestructura
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
# Banner inicial
# ============================================================================

clear
echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║   Apache Flink en Azure HDInsight - Despliegue Automatizado     ║
║   INTEP - Ciencia de Datos - Clase 10                          ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

# ============================================================================
# Información importante
# ============================================================================

print_header "INFORMACIÓN IMPORTANTE"

echo "Este script creará la siguiente infraestructura en Azure:"
echo ""
echo "   Recursos:"
echo "     - Resource Group (rg-intep-flink-dev)"
echo "     - Storage Account con ADLS Gen2"
echo "     - HDInsight Kafka Cluster (5 nodos)"
echo "     - Virtual Network y Subnet"
echo "     - Network Security Group"
echo ""
echo "   Costos estimados:"
echo "     - ~$0.48/hora (~$350/mes)"
echo "     - Azure for Students tiene $100 de crédito"
echo ""
echo "    Tiempo estimado de despliegue:"
echo "     - 15-20 minutos"
echo ""

read -p "¿Deseas continuar con el despliegue? (s/n): " CONTINUAR

if [ "$CONTINUAR" != "s" ] && [ "$CONTINUAR" != "S" ]; then
    print_warning "Despliegue cancelado por el usuario"
    exit 0
fi

# ============================================================================
# Verificar prerrequisitos
# ============================================================================

print_header "1. Verificando prerrequisitos"

# Verificar Azure CLI
if ! command -v az &> /dev/null; then
    print_error "Azure CLI no está instalado"
    exit 1
fi
print_success "Azure CLI instalado"

# Verificar Terraform
if ! command -v terraform &> /dev/null; then
    print_error "Terraform no está instalado"
    exit 1
fi
print_success "Terraform instalado: $(terraform version | head -n1)"

# Verificar login en Azure
if ! az account show &> /dev/null; then
    print_error "No estás autenticado en Azure"
    echo "Ejecuta: az login"
    exit 1
fi

SUBSCRIPTION=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
print_success "Autenticado en Azure"
print_info "Suscripción: $SUBSCRIPTION"
print_info "ID: $SUBSCRIPTION_ID"

# ============================================================================
# Cambiar al directorio de Terraform
# ============================================================================

print_header "2. Preparando directorio de trabajo"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

cd "$TERRAFORM_DIR"
print_success "Directorio: $TERRAFORM_DIR"

# ============================================================================
# Verificar terraform.tfvars
# ============================================================================

print_header "3. Verificando configuración"

if [ ! -f "terraform.tfvars" ]; then
    print_error "No se encontró terraform.tfvars"
    exit 1
fi

print_success "Archivo terraform.tfvars encontrado"

# Mostrar configuración (sin mostrar contraseñas)
print_info "Configuración actual:"
grep -v "password\|ssh_public_key" terraform.tfvars | grep "=" | sed 's/^/  /'

# ============================================================================
# Inicializar Terraform
# ============================================================================

print_header "4. Inicializando Terraform"

print_info "Descargando providers..."
terraform init

print_success "Terraform inicializado correctamente"

# ============================================================================
# Validar configuración
# ============================================================================

print_header "5. Validando configuración"

terraform validate

print_success "Configuración válida"

# ============================================================================
# Generar plan de ejecución
# ============================================================================

print_header "6. Generando plan de ejecución"

print_info "Calculando cambios..."
terraform plan -out=tfplan

print_success "Plan generado y guardado en tfplan"

# ============================================================================
# Confirmar aplicación
# ============================================================================

print_header "7. Confirmación final"

echo ""
echo -e "${YELLOW}ATENCIÓN:${NC} El despliegue tardará aproximadamente 15-20 minutos"
echo "          y comenzará a generar costos en Azure."
echo ""
read -p "¿Confirmas que deseas aplicar el plan? (escribe 'yes' para confirmar): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_warning "Despliegue cancelado por el usuario"
    print_info "El plan se guardó en tfplan. Puedes aplicarlo más tarde con:"
    echo "  cd $TERRAFORM_DIR"
    echo "  terraform apply tfplan"
    exit 0
fi

# ============================================================================
# Aplicar Terraform
# ============================================================================

print_header "8. Desplegando infraestructura"

print_info "Iniciando despliegue..."
echo ""
echo -e "${YELLOW}Este proceso tomará ~15-20 minutos. Por favor espera...${NC}"
echo ""

# Aplicar con timestamp
START_TIME=$(date +%s)
terraform apply tfplan
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

print_success "Infraestructura desplegada exitosamente"
print_info "Tiempo total: ${MINUTES}m ${SECONDS}s"

# ============================================================================
# Guardar outputs
# ============================================================================

print_header "9. Guardando información de despliegue"

print_info "Extrayendo outputs de Terraform..."
terraform output -json > ../terraform_outputs.json

# Extraer valores importantes
CLUSTER_NAME=$(terraform output -raw cluster_name)
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
SSH_COMMAND=$(terraform output -raw ssh_command)
AMBARI_URL=$(terraform output -raw ambari_web_url)

print_success "Outputs guardados en terraform_outputs.json"

# ============================================================================
# Obtener Storage Key
# ============================================================================

print_info "Obteniendo Storage Account Key..."
STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" -o tsv)

# Guardar en archivo .env
cat > ../.env <<EOF
# Configuración generada automáticamente el $(date)
AZURE_STORAGE_ACCOUNT=$STORAGE_ACCOUNT
AZURE_STORAGE_KEY=$STORAGE_KEY
CLUSTER_NAME=$CLUSTER_NAME
RESOURCE_GROUP=$RESOURCE_GROUP
SSH_COMMAND=$SSH_COMMAND
AMBARI_URL=$AMBARI_URL
EOF

print_success "Credenciales guardadas en .env"

# ============================================================================
# Subir código a Storage
# ============================================================================

print_header "10. Subiendo código a Azure Storage"

cd "$SCRIPT_DIR"

print_info "Subiendo flink_streaming_hdinsight.py..."
az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name scripts \
    --name flink_streaming.py \
    --file flink_streaming_hdinsight.py \
    --overwrite \
    --only-show-errors

print_info "Subiendo requirements.txt..."
az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name scripts \
    --name requirements.txt \
    --file requirements.txt \
    --overwrite \
    --only-show-errors

print_success "Código subido exitosamente"

# ============================================================================
# Generar resumen
# ============================================================================

print_header "11. Generando resumen de despliegue"

SUMMARY_FILE="$SCRIPT_DIR/DEPLOYMENT_SUMMARY.txt"

cat > "$SUMMARY_FILE" <<EOF
========================================
Resumen de Despliegue - Apache Flink
========================================
Fecha: $(date)
Duración: ${MINUTES}m ${SECONDS}s

RECURSOS CREADOS:
  - Resource Group: $RESOURCE_GROUP
  - Cluster HDInsight: $CLUSTER_NAME
  - Storage Account: $STORAGE_ACCOUNT
  - Región: East US

CONEXIONES:
  - SSH: $SSH_COMMAND
  - Ambari Web UI: $AMBARI_URL
  - Flink Web UI: Se configurará vía SSH tunneling

CREDENCIALES:
  - Usuario: adminuser
  - Contraseña: Ver terraform.tfvars
  - Storage Key: Ver archivo .env

ARCHIVOS IMPORTANTES:
  - terraform_outputs.json: Outputs completos de Terraform
  - .env: Variables de entorno
  - DEPLOYMENT_SUMMARY.txt: Este resumen

PRÓXIMOS PASOS:
  1. Conectarse al cluster:
     $SSH_COMMAND
     
  2. Configurar Apache Flink (en el cluster SSH):
     # Descargar Flink
     cd /tmp
     wget https://archive.apache.org/dist/flink/flink-1.17.2/flink-1.17.2-bin-scala_2.12.tgz
     tar -xzf flink-1.17.2-bin-scala_2.12.tgz
     sudo mv flink-1.17.2 /opt/flink
     
     # Configurar variables
     echo 'export FLINK_HOME=/opt/flink' >> ~/.bashrc
     echo 'export PATH=\$PATH:\$FLINK_HOME/bin' >> ~/.bashrc
     source ~/.bashrc
     
     # Instalar PyFlink
     sudo apt-get update
     sudo apt-get install -y python3-pip python3-venv
     python3 -m venv ~/flink-env
     source ~/flink-env/bin/activate
     pip install apache-flink pandas azure-storage-file-datalake
     
     # Iniciar Flink
     /opt/flink/bin/start-cluster.sh
     
  3. Crear túnel SSH para Flink UI (en tu máquina local):
     ssh -L 8081:localhost:8081 $SSH_COMMAND
     Luego abrir: http://localhost:8081
     
  4. Ejecutar el código de streaming:
     source ~/flink-env/bin/activate
     export AZURE_STORAGE_ACCOUNT=$STORAGE_ACCOUNT
     export AZURE_STORAGE_KEY=<ver .env>
     python ~/flink_streaming.py

COSTOS:
  - Estimado: ~\$0.48/hora (~\$350/mes)
  - Para detener: az hdinsight stop --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP
  - Para eliminar: cd terraform && terraform destroy

COMANDOS ÚTILES:
  - Ver recursos: az resource list --resource-group $RESOURCE_GROUP --output table
  - Ver logs: ssh $SSH_COMMAND "tail -f /opt/flink/log/*.log"
  - Detener cluster: az hdinsight stop --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP
  - Eliminar todo: cd $TERRAFORM_DIR && terraform destroy

========================================
EOF

print_success "Resumen guardado en DEPLOYMENT_SUMMARY.txt"

# ============================================================================
# Resumen final en pantalla
# ============================================================================

print_header "🎉 DESPLIEGUE COMPLETADO EXITOSAMENTE"

echo ""
echo -e "${GREEN}✓ Infraestructura creada correctamente${NC}"
echo ""
echo " Información del cluster:"
echo "  • Resource Group: ${BLUE}$RESOURCE_GROUP${NC}"
echo "  • Cluster Name: ${BLUE}$CLUSTER_NAME${NC}"
echo "  • Storage Account: ${BLUE}$STORAGE_ACCOUNT${NC}"
echo ""
echo " Conexiones:"
echo "  • SSH: ${BLUE}$SSH_COMMAND${NC}"
echo "  • Ambari Web UI: ${BLUE}$AMBARI_URL${NC}"
echo "  • Usuario: ${BLUE}adminuser${NC}"
echo "  • Contraseña: Ver terraform.tfvars"
echo ""
echo " Próximos pasos:"
echo "  1. Conectarse al cluster:"
echo "     ${YELLOW}$SSH_COMMAND${NC}"
echo ""
echo "  2. Configurar Apache Flink (ver DEPLOYMENT_SUMMARY.txt para comandos completos)"
echo ""
echo "  3. Ver Flink Web UI (crear túnel SSH primero):"
echo "     ${YELLOW}ssh -L 8081:localhost:8081 $SSH_COMMAND${NC}"
echo "     Luego abrir: ${BLUE}http://localhost:8081${NC}"
echo ""
echo " Archivos generados:"
echo "  • ${BLUE}terraform_outputs.json${NC} - Outputs de Terraform"
echo "  • ${BLUE}.env${NC} - Variables de entorno"
echo "  • ${BLUE}DEPLOYMENT_SUMMARY.txt${NC} - Resumen completo"
echo ""
echo " Importante - Costos:"
echo "  • Estimado: ~\$0.48/hora (~\$350/mes)"
echo "  • Para ${RED}detener${NC} el cluster (evitar costos):"
echo "    ${YELLOW}az hdinsight stop --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP${NC}"
echo ""
echo "  • Para ${RED}eliminar${NC} todo (liberar recursos):"
echo "    ${YELLOW}cd $TERRAFORM_DIR && terraform destroy${NC}"
echo ""
echo " Guía completa disponible en: ${BLUE}DEPLOY_GUIDE.md${NC}"
echo ""
print_success "¡Todo listo para usar Apache Flink en Azure!"
echo ""

# ============================================================================
# Abrir archivos importantes
# ============================================================================

read -p "¿Deseas abrir el resumen de despliegue? (s/n): " OPEN_SUMMARY

if [ "$OPEN_SUMMARY" = "s" ] || [ "$OPEN_SUMMARY" = "S" ]; then
    if command -v cat &> /dev/null; then
        cat "$SUMMARY_FILE"
    fi
fi

print_info "Despliegue finalizado. Revisa DEPLOYMENT_SUMMARY.txt para más detalles."
