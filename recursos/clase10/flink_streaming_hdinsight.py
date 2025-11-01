"""
Script para subir código de streaming a Azure HDInsight
Este script adapta el notebook de Flink para ejecutarse en HDInsight
"""

import time
import random
from datetime import datetime, timedelta
import pandas as pd
from pyflink.table import EnvironmentSettings, TableEnvironment
from azure.storage.filedatalake import DataLakeServiceClient
import os

# ============================================================================
# Configuración de Azure Storage
# ============================================================================

STORAGE_ACCOUNT_NAME = os.getenv('AZURE_STORAGE_ACCOUNT')
STORAGE_ACCOUNT_KEY = os.getenv('AZURE_STORAGE_KEY')
CONTAINER_NAME = 'flink-data'

def get_storage_client():
    """Obtiene cliente de Azure Data Lake Storage"""
    account_url = f"https://{STORAGE_ACCOUNT_NAME}.dfs.core.windows.net"
    service_client = DataLakeServiceClient(
        account_url=account_url,
        credential=STORAGE_ACCOUNT_KEY
    )
    return service_client

# ============================================================================
# Generación de eventos (igual que en el notebook)
# ============================================================================

def generar_eventos(n=100):
    """Genera n eventos sintéticos de transacciones"""
    regiones = ['Norte', 'Sur', 'Este', 'Oeste', 'Centro']
    eventos = []
    base_time = datetime.now()
    
    for i in range(n):
        evento = {
            'timestamp': (base_time + timedelta(seconds=i)).isoformat(),
            'user_id': f"user_{random.randint(1, 50)}",
            'product_id': f"prod_{random.randint(100, 120)}",
            'amount': round(random.uniform(10.0, 500.0), 2),
            'region': random.choice(regiones)
        }
        eventos.append(evento)
    
    return pd.DataFrame(eventos)

# ============================================================================
# Configuración de Flink
# ============================================================================

def setup_flink_environment():
    """Configura el entorno de Flink para streaming en HDInsight"""
    print("Configurando entorno Apache Flink...")
    
    # Crear entorno en modo streaming (en HDInsight)
    env_settings = EnvironmentSettings.in_streaming_mode()
    table_env = TableEnvironment.create(env_settings)
    
    # Configurar checkpointing para fault tolerance
    table_env.get_config().get_configuration().set_string(
        "execution.checkpointing.interval", "10s"
    )
    
    print("✓ Entorno Flink configurado correctamente")
    return table_env

# ============================================================================
# Job de Flink: Análisis de transacciones en tiempo real
# ============================================================================

def run_streaming_analytics():
    """
    Job principal de Flink para análisis de transacciones en tiempo real
    """
    table_env = setup_flink_environment()
    
    print("Generando datos de transacciones...")
    df_eventos = generar_eventos(1000)
    df_eventos['timestamp'] = pd.to_datetime(df_eventos['timestamp'])
    
    # Registrar tabla en Flink
    tabla_eventos = table_env.from_pandas(df_eventos)
    table_env.create_temporary_view("transacciones", tabla_eventos)
    
    print("✓ Tabla 'transacciones' registrada en Flink")
    
    # ========================================================================
    # Query 1: Transacciones de alto valor (>$200)
    # ========================================================================
    print("\n📊 Análisis 1: Transacciones de alto valor")
    
    query_alto_valor = table_env.sql_query("""
        SELECT 
            DATE_FORMAT(`timestamp`, 'yyyy-MM-dd HH:mm:ss') as event_time,
            user_id, 
            product_id, 
            amount, 
            region
        FROM transacciones
        WHERE amount > 200
        ORDER BY amount DESC
    """)
    
    resultado1 = query_alto_valor.limit(10).to_pandas()
    print(f"  → {len(resultado1)} transacciones de alto valor detectadas")
    print(resultado1)
    
    # ========================================================================
    # Query 2: Agregación por región
    # ========================================================================
    print("\n📊 Análisis 2: Ventas por región")
    
    query_regiones = table_env.sql_query("""
        SELECT 
            region, 
            COUNT(*) as num_transacciones,
            SUM(amount) as total_ventas,
            AVG(amount) as promedio_venta,
            MIN(amount) as min_venta,
            MAX(amount) as max_venta
        FROM transacciones
        GROUP BY region
        ORDER BY total_ventas DESC
    """)
    
    resultado2 = query_regiones.to_pandas()
    print(resultado2)
    
    # ========================================================================
    # Query 3: Detección de fraude (usuarios con muchas transacciones)
    # ========================================================================
    print("\n🚨 Análisis 3: Detección de actividad sospechosa")
    
    query_fraude = table_env.sql_query("""
        SELECT 
            user_id,
            COUNT(*) as num_transacciones,
            SUM(amount) as total_amount,
            AVG(amount) as promedio_amount,
            MIN(`timestamp`) as primera_transaccion,
            MAX(`timestamp`) as ultima_transaccion
        FROM transacciones
        GROUP BY user_id
        HAVING COUNT(*) > 5
        ORDER BY num_transacciones DESC
    """)
    
    resultado3 = query_fraude.to_pandas()
    print(f"  → {len(resultado3)} usuarios con actividad sospechosa detectados")
    print(resultado3)
    
    # ========================================================================
    # Query 4: Top productos más vendidos
    # ========================================================================
    print("\n🏆 Análisis 4: Top productos más vendidos")
    
    query_productos = table_env.sql_query("""
        SELECT 
            product_id, 
            COUNT(*) as ventas,
            SUM(amount) as revenue,
            AVG(amount) as precio_promedio
        FROM transacciones
        GROUP BY product_id
        ORDER BY ventas DESC
        LIMIT 5
    """)
    
    resultado4 = query_productos.to_pandas()
    print(resultado4)
    
    # ========================================================================
    # Guardar resultados en Azure Storage
    # ========================================================================
    print("\n💾 Guardando resultados en Azure Storage...")
    
    try:
        service_client = get_storage_client()
        file_system_client = service_client.get_file_system_client(CONTAINER_NAME)
        
        # Crear directorio de resultados
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        results_dir = f"resultados/{timestamp}"
        
        # Guardar cada resultado
        for i, (nombre, df) in enumerate([
            ('alto_valor', resultado1),
            ('regiones', resultado2),
            ('fraude', resultado3),
            ('top_productos', resultado4)
        ], 1):
            file_name = f"{results_dir}/{nombre}.csv"
            file_client = file_system_client.get_file_client(file_name)
            
            csv_content = df.to_csv(index=False)
            file_client.upload_data(csv_content, overwrite=True)
            
            print(f"  ✓ Resultado {i} guardado: {file_name}")
        
        print(f"\n✅ Análisis completado exitosamente!")
        print(f"📁 Resultados guardados en: abfss://{CONTAINER_NAME}@{STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/{results_dir}/")
        
    except Exception as e:
        print(f"⚠️ Error al guardar en Storage: {e}")
        print("Los resultados se mostraron en consola pero no se guardaron en Azure Storage")

# ============================================================================
# Simulación de streaming continuo
# ============================================================================

def simular_streaming_continuo(duracion_minutos=5):
    """
    Simula un stream continuo de eventos por X minutos
    En producción, esto leería de Kafka, Event Hubs, etc.
    """
    print(f"\n🔄 Iniciando simulación de streaming continuo ({duracion_minutos} minutos)...")
    
    table_env = setup_flink_environment()
    regiones = ['Norte', 'Sur', 'Este', 'Oeste', 'Centro']
    
    inicio = time.time()
    contador = 0
    
    while (time.time() - inicio) < (duracion_minutos * 60):
        # Generar lote de eventos
        eventos = []
        for _ in range(10):  # 10 eventos por lote
            evento = {
                'timestamp': datetime.now().isoformat(),
                'user_id': f"user_{random.randint(1, 50)}",
                'product_id': f"prod_{random.randint(100, 120)}",
                'amount': round(random.uniform(10.0, 500.0), 2),
                'region': random.choice(regiones)
            }
            eventos.append(evento)
        
        # Procesar lote
        df_lote = pd.DataFrame(eventos)
        df_lote['timestamp'] = pd.to_datetime(df_lote['timestamp'])
        
        tabla_lote = table_env.from_pandas(df_lote)
        table_env.create_temporary_view(f"lote_{contador}", tabla_lote)
        
        # Análisis en tiempo real
        query = table_env.sql_query(f"""
            SELECT 
                region,
                COUNT(*) as transacciones,
                SUM(amount) as total
            FROM lote_{contador}
            GROUP BY region
        """)
        
        resultado = query.to_pandas()
        
        print(f"\r[Lote {contador}] Procesados {len(eventos)} eventos | "
              f"Regiones activas: {len(resultado)} | "
              f"Tiempo: {int(time.time() - inicio)}s", end='')
        
        contador += 1
        time.sleep(2)  # Esperar 2 segundos entre lotes
    
    print(f"\n✅ Streaming continuo finalizado. Total de lotes procesados: {contador}")

# ============================================================================
# Main
# ============================================================================

if __name__ == "__main__":
    print("=" * 80)
    print("🚀 Apache Flink - Análisis de Transacciones en Tiempo Real")
    print("=" * 80)
    print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Storage Account: {STORAGE_ACCOUNT_NAME}")
    print("=" * 80)
    
    # Verificar variables de entorno
    if not STORAGE_ACCOUNT_NAME or not STORAGE_ACCOUNT_KEY:
        print("⚠️ ADVERTENCIA: Variables de entorno no configuradas")
        print("   Configura AZURE_STORAGE_ACCOUNT y AZURE_STORAGE_KEY")
        print("   Los resultados no se guardarán en Azure Storage")
    
    try:
        # Ejecutar análisis batch
        run_streaming_analytics()
        
        # Preguntar si ejecutar streaming continuo
        print("\n" + "=" * 80)
        respuesta = input("\n¿Deseas ejecutar simulación de streaming continuo? (s/n): ")
        
        if respuesta.lower() in ['s', 'si', 'sí', 'yes', 'y']:
            minutos = int(input("¿Cuántos minutos? (default: 5): ") or "5")
            simular_streaming_continuo(duracion_minutos=minutos)
        
        print("\n" + "=" * 80)
        print("✅ Proceso finalizado exitosamente")
        print("=" * 80)
        
    except KeyboardInterrupt:
        print("\n\n⚠️ Proceso interrumpido por el usuario")
    except Exception as e:
        print(f"\n\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
