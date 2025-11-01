# ============================================================================
# Guía de Despliegue - Apache Flink en Azure HDInsight
# ============================================================================

## 📋 Prerrequisitos

Antes de comenzar, asegúrate de tener instalado:

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Terraform](https://www.terraform.io/downloads) (>= 1.0)
- Una suscripción activa de Azure
- Llave SSH generada (`ssh-keygen -t rsa -b 4096`)

## 🚀 Paso 1: Configurar credenciales de Azure

```bash
# Iniciar sesión en Azure
az login

# Verificar la suscripción activa
az account show

# Si tienes múltiples suscripciones, selecciona la correcta
az account set --subscription "TU_SUBSCRIPTION_ID"
```

## 📝 Paso 2: Configurar variables de Terraform

```bash
# Navegar al directorio de Terraform
cd recursos/clase10/terraform

# Copiar el archivo de ejemplo
cp terraform.tfvars.example terraform.tfvars

# Editar con tus valores
nano terraform.tfvars  # o usa tu editor preferido
```

**Valores importantes a configurar:**

```hcl
# Nombre único del proyecto
project_name = "intep-flink"

# Contraseña segura (mínimo 10 caracteres)
admin_password = "TuContraseñaSegura!123"

# Tu llave SSH pública
ssh_public_key = "ssh-rsa AAAAB3Nza... tu-email@ejemplo.com"
```

**⚠️ Generación de llave SSH (si no tienes una):**

```bash
# Generar llave SSH
ssh-keygen -t rsa -b 4096 -C "tu-email@ejemplo.com"

# Ver tu llave pública
cat ~/.ssh/id_rsa.pub
```

## 🏗️ Paso 3: Desplegar infraestructura con Terraform

```bash
# Inicializar Terraform (primera vez)
terraform init

# Ver el plan de ejecución
terraform plan

# Aplicar la configuración (esto toma ~15-20 minutos)
terraform apply

# Confirmar con: yes
```

**Salida esperada:**

```
Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

Outputs:

ambari_web_url = "https://hdi-intep-flink-dev.azurehdinsight.net"
cluster_endpoint = "https://hdi-intep-flink-dev.azurehdinsight.net"
cluster_name = "hdi-intep-flink-dev"
flink_data_container = "abfss://flink-data@stintepflinkdevxxx.dfs.core.windows.net/"
resource_group_name = "rg-intep-flink-dev"
ssh_command = "ssh adminuser@hdi-intep-flink-dev-ssh.azurehdinsight.net"
storage_account_name = "stintepflinkdevxxx"
```

## 🔧 Paso 4: Configurar Apache Flink en el cluster

### 4.1 Conectarse al cluster via SSH

```bash
# Copiar el comando SSH del output de Terraform
ssh adminuser@hdi-intep-flink-dev-ssh.azurehdinsight.net

# Aceptar la huella digital: yes
```

### 4.2 Instalar Apache Flink

```bash
# Una vez conectado al cluster, ejecuta:
cd /tmp

# Descargar Flink
FLINK_VERSION="1.17.2"
wget https://archive.apache.org/dist/flink/flink-${FLINK_VERSION}/flink-${FLINK_VERSION}-bin-scala_2.12.tgz

# Extraer
tar -xzf flink-${FLINK_VERSION}-bin-scala_2.12.tgz
sudo mv flink-${FLINK_VERSION} /opt/flink
sudo chown -R $USER:$USER /opt/flink

# Configurar variables de entorno
echo 'export FLINK_HOME=/opt/flink' >> ~/.bashrc
echo 'export PATH=$PATH:$FLINK_HOME/bin' >> ~/.bashrc
source ~/.bashrc
```

### 4.3 Instalar PyFlink y dependencias

```bash
# Instalar Python y pip
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv

# Crear entorno virtual
python3 -m venv ~/flink-env
source ~/flink-env/bin/activate

# Instalar dependencias
pip install apache-flink pandas azure-storage-file-datalake
```

### 4.4 Configurar conexión a Azure Storage

```bash
# Obtener la key del storage account (desde tu máquina local)
az storage account keys list \
  --account-name stintepflinkdevxxx \
  --resource-group rg-intep-flink-dev \
  --query "[0].value" -o tsv

# En el cluster SSH, configurar Flink
cat >> /opt/flink/conf/flink-conf.yaml <<EOF

# Azure Storage Configuration
fs.azure.account.key.stintepflinkdevxxx.dfs.core.windows.net: TU_STORAGE_KEY_AQUÍ
EOF
```

### 4.5 Iniciar Flink

```bash
# Iniciar cluster de Flink
/opt/flink/bin/start-cluster.sh

# Verificar que está corriendo
jps  # Deberías ver StandaloneSessionClusterEntrypoint y TaskManagerRunner
```

## 📤 Paso 5: Subir y ejecutar código de streaming

### 5.1 Preparar el código localmente

```bash
# En tu máquina local, desde el directorio del proyecto
cd recursos/clase10

# Configurar variables de entorno
export AZURE_STORAGE_ACCOUNT="stintepflinkdevxxx"
export AZURE_STORAGE_KEY="tu-storage-key"

# Probar localmente (opcional)
python flink_streaming_hdinsight.py
```

### 5.2 Subir código al cluster

```bash
# Desde tu máquina local
scp flink_streaming_hdinsight.py adminuser@hdi-intep-flink-dev-ssh.azurehdinsight.net:~/

# También puedes subirlo a Azure Storage
az storage blob upload \
  --account-name stintepflinkdevxxx \
  --container-name scripts \
  --name flink_streaming.py \
  --file flink_streaming_hdinsight.py
```

### 5.3 Ejecutar el job de Flink

```bash
# Conectarse al cluster
ssh adminuser@hdi-intep-flink-dev-ssh.azurehdinsight.net

# Activar entorno virtual
source ~/flink-env/bin/activate

# Configurar variables de entorno
export AZURE_STORAGE_ACCOUNT="stintepflinkdevxxx"
export AZURE_STORAGE_KEY="tu-storage-key"

# Ejecutar con PyFlink
flink run -py ~/flink_streaming_hdinsight.py

# O ejecutar directamente con Python
python ~/flink_streaming_hdinsight.py
```

## 📊 Paso 6: Monitorear la ejecución

### 6.1 Flink Web UI

```bash
# Crear túnel SSH (desde tu máquina local)
ssh -L 8081:localhost:8081 adminuser@hdi-intep-flink-dev-ssh.azurehdinsight.net

# Abrir en navegador:
# http://localhost:8081
```

### 6.2 Ambari Web UI

```bash
# Abrir en navegador:
# https://hdi-intep-flink-dev.azurehdinsight.net
# Usuario: adminuser
# Contraseña: la que configuraste en terraform.tfvars
```

### 6.3 Ver logs

```bash
# En el cluster SSH
tail -f /opt/flink/log/flink-*-standalonesession-*.log

# Ver logs de TaskManager
tail -f /opt/flink/log/flink-*-taskexecutor-*.log
```

### 6.4 Ver resultados en Azure Storage

```bash
# Listar resultados generados
az storage blob list \
  --account-name stintepflinkdevxxx \
  --container-name flink-data \
  --prefix resultados/ \
  --output table

# Descargar un resultado
az storage blob download \
  --account-name stintepflinkdevxxx \
  --container-name flink-data \
  --name resultados/20251031_143022/regiones.csv \
  --file regiones.csv
```

## 🧹 Paso 7: Limpiar recursos (opcional)

```bash
# ADVERTENCIA: Esto eliminará TODOS los recursos creados

cd recursos/clase10/terraform

# Ver qué se va a eliminar
terraform plan -destroy

# Destruir todos los recursos
terraform destroy

# Confirmar con: yes
```

## 💰 Estimación de costos

**Configuración por defecto (Standard_D3_v2, 2 workers):**

| Recurso | Costo aproximado (USD) |
|---------|------------------------|
| HDInsight Cluster (2 workers) | ~$350/mes (~$0.48/hora) |
| Storage Account (100GB) | ~$2/mes |
| Networking | ~$5/mes |
| **Total estimado** | **~$357/mes** |

**💡 Consejos para reducir costos:**

1. **Detener el cluster cuando no lo uses:**
   ```bash
   az hdinsight stop --name hdi-intep-flink-dev --resource-group rg-intep-flink-dev
   ```

2. **Usar tier Development en lugar de Standard:**
   ```hcl
   cluster_tier = "Standard"  # Cambiar a "Standard" (no hay tier Development para HDInsight)
   ```

3. **Reducir número de workers:**
   ```hcl
   worker_node_count = 1  # Mínimo para desarrollo
   ```

4. **Eliminar recursos después de la clase:**
   ```bash
   terraform destroy
   ```

## 🐛 Troubleshooting

### Error: "Insufficient quota"

**Solución:** Aumenta tu cuota de vCPUs en Azure:

```bash
az vm list-usage --location "East US" --output table
```

### Error: "SSH connection refused"

**Solución:** Espera ~5 minutos después de que termine `terraform apply`. El cluster necesita tiempo para inicializar.

### Error: "ImportError: No module named pyflink"

**Solución:** Asegúrate de activar el entorno virtual:

```bash
source ~/flink-env/bin/activate
pip install apache-flink
```

### Error: "Unable to authenticate with Azure Storage"

**Solución:** Verifica que la storage key esté correctamente configurada:

```bash
# Obtener la key correcta
az storage account keys list \
  --account-name stintepflinkdevxxx \
  --resource-group rg-intep-flink-dev

# Actualizar en flink-conf.yaml
nano /opt/flink/conf/flink-conf.yaml
```

## 📚 Recursos adicionales

- **Documentación de HDInsight:** https://docs.microsoft.com/azure/hdinsight/
- **Apache Flink Docs:** https://flink.apache.org/docs/stable/
- **PyFlink Tutorial:** https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/python/
- **Terraform Azure Provider:** https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs

## 📞 Soporte

Si encuentras problemas:

1. Revisa los logs de Flink: `tail -f /opt/flink/log/*.log`
2. Verifica el estado del cluster en Ambari Web UI
3. Consulta la documentación oficial de Azure HDInsight
4. Contacta al instructor del curso

---

**✅ ¡Listo!** Ahora tienes un cluster de Apache Flink completamente funcional en Azure HDInsight, listo para procesar streams de datos en tiempo real.
