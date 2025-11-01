# Apache Flink — Análisis de Datos en Tiempo Real

## Descripción
Laboratorio completo de **Apache Flink (PyFlink)** para procesamiento de flujos de datos en tiempo real. Incluye ejemplos prácticos de:
- Configuración de entorno Flink
- Simulación de eventos streaming (transacciones e-commerce)
- Consultas SQL sobre streams
- Ventanas temporales (Tumbling Windows)
- Detección de patrones y fraudes
- Métricas operacionales en tiempo real
- Visualizaciones

## Requisitos
- Python 3.8+
- Apache Flink (PyFlink)
- pandas, matplotlib
- Java 8+ (requerido por Flink)

## Instalación rápida

### macOS
```bash
# Instalar Java (si no está instalado)
brew install openjdk@11

# Instalar PyFlink
pip install apache-flink pandas matplotlib
```

### Linux/Windows
```bash
# Asegúrate de tener Java 8+ instalado
# Luego instala PyFlink
pip install apache-flink pandas matplotlib
```

## Estructura del notebook
1. **Setup:** configuración de entorno Flink
2. **Simulación de datos:** generador de eventos sintéticos
3. **SQL sobre streams:** filtrado, agregaciones
4. **Ventanas temporales:** Tumbling Windows de 10s, 30s, 60s
5. **Detección de fraudes:** identificación de usuarios con actividad sospechosa
6. **Dashboard en tiempo real:** métricas operacionales
7. **Streaming continuo:** simulación de eventos en vivo
8. **Conceptos clave:** Event Time, Watermarks, tipos de ventanas, estado

## Casos de uso cubiertos
- **E-commerce:** análisis de transacciones en tiempo real
- **Detección de fraudes:** patrones de comportamiento anómalo
- **Métricas operacionales:** dashboards en vivo
- **Top-K queries:** productos/usuarios más activos

## Actividades para entregar
1. Generar 500 eventos y cargar en Flink
2. Top 5 usuarios con mayor gasto
3. Agregaciones por ventanas de 20s
4. Detección de outliers (transacciones > $400)
5. Simulación streaming de 30s
6. (Opcional) Integración con Kafka

## Conceptos clave explicados
- **Event Time vs Processing Time**
- **Watermarks** (manejo de eventos fuera de orden)
- **Tipos de ventanas:** Tumbling, Sliding, Session
- **Estado** en Flink
- **Exactly-Once processing**

## Ejecución
Abre el notebook en VS Code, Jupyter o Databricks y ejecuta las celdas en orden. Asegúrate de tener Java instalado antes de ejecutar.

## Recursos adicionales
- [Documentación oficial de Flink](https://flink.apache.org/)
- [PyFlink docs](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/python/)
- [Flink Training (GitHub)](https://github.com/apache/flink-training)

## Notas
- El notebook incluye simulación local de eventos; en producción usarías Kafka, Kinesis o similar.
- Para ambientes de producción, considera configurar clusters Flink distribuidos.
- El ejemplo es didáctico y simplificado; adapta según las necesidades de tu infraestructura.

## Duración sugerida
2–2.5 horas (incluye instalación, ejecución y actividades)
