#!/bin/bash

# Script de recuperación del cluster Elasticsearch
# Autor: DevOps Expert
# Fecha: $(date)

ELASTIC_USER="elastic"
ELASTIC_PASS="Alandalus2425"
ELASTIC_HOST="https://192.168.220.101:9200"

echo "=== RECUPERACIÓN DEL CLUSTER ELASTICSEARCH ==="
echo "Fecha: $(date)"
echo "=========================================="

# Función para mostrar estado del cluster
check_cluster_status() {
    echo "📊 Verificando estado del cluster..."
    curl -k -u $ELASTIC_USER:$ELASTIC_PASS $ELASTIC_HOST/_cluster/health?pretty
    echo ""
}

# Función para mostrar shards no asignados
check_unassigned_shards() {
    echo "🔍 Verificando shards no asignados..."
    curl -k -u $ELASTIC_USER:$ELASTIC_PASS $ELASTIC_HOST/_cat/shards?v
    echo ""
    
    echo "📋 Explicación de asignación de shards..."
    curl -k -u $ELASTIC_USER:$ELASTIC_PASS $ELASTIC_HOST/_cluster/allocation/explain?pretty
    echo ""
}

# Función para habilitar asignación de shards
enable_shard_allocation() {
    echo "🔧 Habilitando asignación de shards..."
    curl -k -u $ELASTIC_USER:$ELASTIC_PASS -X PUT $ELASTIC_HOST/_cluster/settings -H 'Content-Type: application/json' -d'
    {
      "persistent": {
        "cluster.routing.allocation.enable": "all",
        "cluster.routing.rebalance.enable": "all"
      }
    }'
    echo ""
}

# Función para configurar réplicas
configure_replicas() {
    echo "⚙️ Configurando número de réplicas..."
    curl -k -u $ELASTIC_USER:$ELASTIC_PASS -X PUT $ELASTIC_HOST/_all/_settings -H 'Content-Type: application/json' -d'
    {
      "index": {
        "number_of_replicas": 1
      }
    }'
    echo ""
}

# Función para forzar reasignación
force_reroute() {
    echo "🔄 Forzando reasignación de shards..."
    curl -k -u $ELASTIC_USER:$ELASTIC_PASS -X POST $ELASTIC_HOST/_cluster/reroute?retry_failed=true
    echo ""
}

# Función para crear índice de seguridad manualmente si es necesario
create_security_index() {
    echo "🔐 Verificando/Creando índice de seguridad..."
    curl -k -u $ELASTIC_USER:$ELASTIC_PASS -X PUT $ELASTIC_HOST/.security-7 -H 'Content-Type: application/json' -d'
    {
      "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 1,
        "auto_expand_replicas": "0-1"
      }
    }'
    echo ""
}

# Función para configurar contraseñas de usuarios del sistema
setup_passwords() {
    echo "🔑 Configurando contraseñas de usuarios del sistema..."
    
    # Configurar contraseña para kibana_system
    curl -k -u $ELASTIC_USER:$ELASTIC_PASS -X POST $ELASTIC_HOST/_security/user/kibana_system/_password -H 'Content-Type: application/json' -d'
    {
      "password": "Alandalus2425"
    }'
    echo ""
    
    # Configurar contraseña para logstash_system
    curl -k -u $ELASTIC_USER:$ELASTIC_PASS -X POST $ELASTIC_HOST/_security/user/logstash_system/_password -H 'Content-Type: application/json' -d'
    {
      "password": "Alandalus2425"
    }'
    echo ""
    
    # Configurar contraseña para beats_system
    curl -k -u $ELASTIC_USER:$ELASTIC_PASS -X POST $ELASTIC_HOST/_security/user/beats_system/_password -H 'Content-Type: application/json' -d'
    {
      "password": "Alandalus2425"
    }'
    echo ""
}

# Función para mostrar configuración actual
show_current_config() {
    echo "📋 Configuración actual del cluster..."
    curl -k -u $ELASTIC_USER:$ELASTIC_PASS $ELASTIC_HOST/_cluster/settings?pretty
    echo ""
}

# Función para esperar hasta que el cluster esté verde
wait_for_green() {
    echo "⏳ Esperando que el cluster se ponga verde..."
    local counter=0
    local max_attempts=30
    
    while [ $counter -lt $max_attempts ]; do
        local status=$(curl -k -s -u $ELASTIC_USER:$ELASTIC_PASS $ELASTIC_HOST/_cluster/health | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        
        if [ "$status" = "green" ]; then
            echo "✅ Cluster está en estado verde!"
            return 0
        elif [ "$status" = "yellow" ]; then
            echo "⚠️ Cluster está en estado amarillo (intento $((counter+1))/$max_attempts)..."
        else
            echo "❌ Cluster está en estado rojo (intento $((counter+1))/$max_attempts)..."
        fi
        
        sleep 10
        counter=$((counter+1))
    done
    
    echo "⚠️ El cluster no alcanzó el estado verde en el tiempo esperado"
    return 1
}

# Ejecución principal
main() {
    echo "🚀 Iniciando proceso de recuperación..."
    
    # Verificar estado inicial
    check_cluster_status
    
    # Mostrar configuración actual
    show_current_config
    
    # Verificar shards no asignados
    check_unassigned_shards
    
    # Habilitar asignación de shards
    enable_shard_allocation
    
    # Configurar réplicas
    configure_replicas
    
    # Crear índice de seguridad si es necesario
    create_security_index
    
    # Forzar reasignación
    force_reroute
    
    # Esperar un poco para que se procesen los cambios
    echo "⏱️ Esperando 30 segundos para que se procesen los cambios..."
    sleep 30
    
    # Configurar contraseñas de usuarios del sistema
    setup_passwords
    
    # Esperar a que el cluster esté verde
    wait_for_green
    
    # Verificar estado final
    echo "📊 Estado final del cluster:"
    check_cluster_status
    
    echo "✅ Proceso de recuperación completado!"
    echo "📝 Revisa los logs de Docker Compose para más detalles:"
    echo "   docker-compose logs -f elastic01 elastic02 elastic03"
}

# Ejecutar función principal
main
