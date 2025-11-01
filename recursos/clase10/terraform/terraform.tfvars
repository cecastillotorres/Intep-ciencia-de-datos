# ============================================================================
# Configuración de Terraform para Apache Flink en Azure HDInsight
# ============================================================================

# Información del proyecto
project_name = "intep-flink"
environment  = "dev"
location     = "Mexico Central"

# Credenciales de administrador
admin_username = "adminuser"
# IMPORTANTE: Contraseña con al menos 10 caracteres, mayúsculas, minúsculas, números y símbolos
admin_password = "FlinkAdmin2025!"

# Llave SSH pública
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCyvmh6Mr5V0s1VC7G4cqS7jJcGFdwrXe4Flrv2cM4UtrT4+cnmXPJlEpCldeVCj3b3kHI25V6WKPVLLF+Q+RKrHBP/mORO8YrwQTUFBmWFDsqxyeJ7rR6VRNAk6EiCMWDtl20lx0AOorwIm3dPrJ1KDrQlZZCLoIZgzQyclOZQ2UmGyNai14JiGwnrc5a1tTDSbKQWCEa12vndD7nwX+OCfkXTsU0oOyUsBXd8atU+NsPx8oOQGkv0kJDODFwkWgwrFNkjsRWQs1DOnzRd1x4+YryeB4N8zZEbF95sZ8SwFdsUrN0A81qgFTI951rMXZwSIY06uSudS2WJxuquNOzqXsWvaolm4McU2uIfx6aa2jU+FLstM/A63kH3740FZzVNo0od9PBjv+CFc5aR051QRXZqrDQyCoHX/haOeYqsFb4Av6xB5K8qZGuv9lSSnjWgKKKPf8nlNTCWV7jl6D0p51AYnGM9z8ebbKv9fi5qwIAyRN/OaKagoOyPPsCTyRU= cesar@Cesar.local"

# Configuración del cluster (ajustado para Azure for Students)
cluster_tier         = "Standard"
head_node_vm_size    = "Standard_D3_v2"
worker_node_vm_size  = "Standard_D3_v2"
worker_node_count    = 2

# Tags personalizados
tags = {
  Project     = "INTEP Ciencia de Datos"
  Environment = "Development"
  ManagedBy   = "Terraform"
  Purpose     = "Apache Flink Streaming Analytics"
  Course      = "Clase 10 - Stream Processing"
  Owner       = "Cesar Castillo"
}
