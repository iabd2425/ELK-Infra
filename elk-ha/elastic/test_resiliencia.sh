#!/bin/bash

# Script de Consultas de Resiliencia para Cluster Elasticsearch
# Proyecto: ELK High Availability Testing
# Servidor: proyecto-vm1 (192.168.220.101)
# Propósito: Verificar resiliencia y alta disponibilidad del cluster

# Variables de configuración
HOST="${ELASTIC_HOSTS:-https://192.168.220.101:9200}"
CERT="${CA_CERT:-/elk-share/certs/ca/ca.crt}"
INDEX="hoteles"
TIMEOUT=15

# Variables de entorno
FILE_ENV="/home/docker/elk-ha/.env"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Función para imprimir encabezados
print_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

print_subheader() {
    echo -e "\n${BLUE}🔍 $1${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Función para cargar variables de entorno
load_environment() {
    if [ -f "${FILE_ENV}" ]; then
        source ${FILE_ENV}
        print_success "Variables de entorno cargadas desde .env"
    else
        print_warning "Archivo .env no encontrado, usando variables del sistema"
    fi

    if [ -z "$ELASTIC_PASSWORD" ]; then
        print_error "Variable ELASTIC_PASSWORD vacía o no definida"
        exit 1
    fi

    if [ ! -f "$CERT" ]; then
        print_error "Certificado no encontrado en $CERT"
        exit 1
    fi
}

# Función para ejecutar consulta HTTP
execute_query() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local description="$4"
    
    echo -e "\n${PURPLE}🚀 Ejecutando: $description${NC}"
    echo -e "${PURPLE}Endpoint: $method $endpoint${NC}"
    
    if [ -n "$data" ]; then
        echo -e "${PURPLE}Payload:${NC}"
        echo "$data" | jq . 2>/dev/null || echo "$data"
        echo ""
        
        response=$(curl -s -X "$method" "$HOST$endpoint" \
            -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
            --cacert "$CERT" \
            --connect-timeout 5 \
            --max-time "$TIMEOUT" \
            -H 'Content-Type: application/json' \
            -d "$data" 2>/dev/null)
    else
        response=$(curl -s -X "$method" "$HOST$endpoint" \
            -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
            --cacert "$CERT" \
            --connect-timeout 5 \
            --max-time "$TIMEOUT" 2>/dev/null)
    fi
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 0
    else
        print_error "Error en la consulta HTTP"
        return 1
    fi
}

# 1. SALUD GENERAL DEL CLUSTER
check_cluster_health() {
    print_header "SALUD GENERAL DEL CLUSTER"
    
    # Salud básica del cluster
    execute_query "GET" "/_cluster/health" "" "Salud básica del cluster"
    
    # Salud detallada del cluster
    execute_query "GET" "/_cluster/health?level=shards&pretty" "" "Salud detallada por shards"
    
    # Estado de los nodos
    execute_query "GET" "/_cat/nodes?v&h=name,ip,heap.percent,ram.percent,cpu,load_1m,disk.used_percent,node.role,master" "" "Estado de nodos del cluster"
    
    # Asignación de shards
    execute_query "GET" "/_cat/allocation?v" "" "Asignación de almacenamiento por nodo"
}

# 2. ESTADO ESPECÍFICO DEL ÍNDICE HOTELES
check_index_health() {
    print_header "ESTADO DEL ÍNDICE: $INDEX"
    
    # Salud específica del índice
    execute_query "GET" "/_cluster/health/$INDEX?level=shards&pretty" "" "Salud específica del índice $INDEX"
    
    # Información detallada del índice
    execute_query "GET" "/$INDEX/_settings?pretty" "" "Configuración del índice $INDEX"
    
    # Estadísticas del índice
    execute_query "GET" "/$INDEX/_stats?pretty" "" "Estadísticas completas del índice $INDEX"
    
    # Mapping del índice
    execute_query "GET" "/$INDEX/_mapping?pretty" "" "Mapping del índice $INDEX"
}

# 3. DISTRIBUCIÓN DE SHARDS Y RÉPLICAS
check_shard_distribution() {
    print_header "DISTRIBUCIÓN DE SHARDS Y RÉPLICAS"
    
    # Vista general de shards
    execute_query "GET" "/_cat/shards?v" "" "Vista general de todos los shards"
    
    # Shards específicos del índice hoteles
    execute_query "GET" "/_cat/shards/$INDEX?v&h=index,shard,prirep,state,docs,store,node" "" "Shards específicos del índice $INDEX"
    
    # Shards no asignados (crítico para resiliencia)
    execute_query "GET" "/_cat/shards?v&h=index,shard,prirep,state,unassigned.reason,node" "" "Estado de asignación de shards"
    
    # Información de recuperación de shards
    execute_query "GET" "/_cat/recovery/$INDEX?v&active_only=false" "" "Estado de recuperación de shards"
}

# 4. PRUEBAS DE ESCRITURA Y LECTURA
test_read_write_operations() {
    print_header "PRUEBAS DE OPERACIONES DE LECTURA/ESCRITURA"
    
    # Documento de prueba
    local test_doc='{
        "id": "test-resilience-001",
        "nombre": "Hotel Test Resiliencia",
        "localidad": "Test City",
        "provincia": "Test Province",
        "precio": 100,
        "opinion": 4.5,
        "comentarios": 250,
        "descripcion": "Hotel de prueba para verificar resiliencia del cluster",
        "direccion": "Calle Test 123",
        "marca": "Test Brand",
        "fechaEntrada": "2025-06-16",
        "fechaSalida": "2025-06-18",
        "location": {"lat": 40.4168, "lon": -3.7038},
        "servicios": "WiFi, Piscina, Spa",
        "destacados": "Vista panorámica",
        "url": "https://test.hotel.com"
    }'
    
    # Insertar documento de prueba
    execute_query "POST" "/$INDEX/_doc/test-resilience-001" "$test_doc" "Inserción de documento de prueba"
    
    # Forzar refresh del índice
    execute_query "POST" "/$INDEX/_refresh" "" "Refresh del índice para disponibilidad inmediata"
    
    # Leer el documento insertado
    execute_query "GET" "/$INDEX/_doc/test-resilience-001" "" "Lectura de documento de prueba"
    
    # Búsqueda por término
    local search_query='{
        "query": {
            "match": {
                "nombre": "Test Resiliencia"
            }
        }
    }'
    execute_query "POST" "/$INDEX/_search" "$search_query" "Búsqueda de documento de prueba"
    
    # Contar documentos totales
    execute_query "GET" "/$INDEX/_count" "" "Conteo total de documentos"
}

# 5. SIMULACIÓN DE FALLO DE NODO
simulate_node_failure_scenarios() {
    print_header "ESCENARIOS DE SIMULACIÓN DE FALLOS"
    
    print_subheader "Información previa al fallo simulado"
    
    # Estado antes del fallo
    execute_query "GET" "/_cluster/health?wait_for_status=green&timeout=30s" "" "Esperando estado GREEN antes de pruebas"
    
    # Lista de nodos disponibles
    execute_query "GET" "/_cat/nodes?v&h=name,ip,role,master,heap.percent" "" "Nodos disponibles"
    
    print_warning "IMPORTANTE: Para simular fallos reales, necesitarás:"
    echo "1. Detener manualmente un contenedor de Elasticsearch"
    echo "2. Ejecutar las siguientes consultas durante y después del fallo"
    echo "3. Observar cómo el cluster se recupera automáticamente"
    
    print_info "Comandos para simular fallo de nodo:"
    echo "docker stop elk-ha-es01-1  # Detener primer nodo"
    echo "# Ejecutar consultas de monitoreo..."
    echo "docker start elk-ha-es01-1  # Reiniciar nodo"
}

# 6. MONITOREO DURANTE FALLO
monitor_during_failure() {
    print_header "MONITOREO DURANTE FALLO DE NODO"
    
    print_info "Ejecuta estas consultas mientras un nodo está caído:"
    
    # Salud del cluster (debería mostrar YELLOW)
    execute_query "GET" "/_cluster/health?pretty" "" "Salud del cluster durante fallo"
    
    # Nodos activos
    execute_query "GET" "/_cat/nodes?v" "" "Nodos activos durante fallo"
    
    # Estado de shards (algunos deberían estar UNASSIGNED)
    execute_query "GET" "/_cat/shards/$INDEX?v" "" "Estado de shards durante fallo"
    
    # Prueba de lectura durante fallo
    execute_query "GET" "/$INDEX/_doc/test-resilience-001" "" "Prueba de lectura durante fallo"
    
    # Prueba de escritura durante fallo
    local test_doc_failure='{
        "id": "test-during-failure",
        "nombre": "Hotel Durante Fallo",
        "precio": 150,
        "descripcion": "Documento insertado durante fallo de nodo"
    }'
    execute_query "POST" "/$INDEX/_doc/test-during-failure" "$test_doc_failure" "Prueba de escritura durante fallo"
}

# 7. VERIFICACIÓN POST-RECUPERACIÓN
verify_post_recovery() {
    print_header "VERIFICACIÓN POST-RECUPERACIÓN"
    
    # Esperar a que el cluster vuelva a GREEN
    execute_query "GET" "/_cluster/health?wait_for_status=green&timeout=60s&pretty" "" "Esperando recuperación completa"
    
    # Verificar todos los nodos están activos
    execute_query "GET" "/_cat/nodes?v" "" "Verificación de nodos activos"
    
    # Verificar shards reasignados
    execute_query "GET" "/_cat/shards/$INDEX?v" "" "Verificación de reasignación de shards"
    
    # Verificar integridad de datos
    execute_query "GET" "/$INDEX/_count" "" "Conteo final de documentos"
    
    # Buscar documentos de prueba (incluyendo el insertado durante el fallo)
    local search_all_tests='{
        "query": {
            "bool": {
                "should": [
                    {"match": {"id": "test-resilience-001"}},
                    {"match": {"id": "test-during-failure"}}
                ]
            }
        }
    }'
    execute_query "POST" "/$INDEX/_search" "$search_all_tests" "Verificación de documentos de prueba"
    
    # Limpiar documentos de prueba
    execute_query "DELETE" "/$INDEX/_doc/test-resilience-001" "" "Limpieza: eliminando documento de prueba 1"
    execute_query "DELETE" "/$INDEX/_doc/test-during-failure" "" "Limpieza: eliminando documento de prueba 2"
}

# 8. PRUEBAS DE PLANTILLAS DE ÍNDICE
test_index_templates() {
    print_header "PRUEBAS DE PLANTILLAS DE ÍNDICE"
    
    # Verificar plantillas existentes
    execute_query "GET" "/_index_template/scraper-template" "" "Verificación plantilla scraper"
    execute_query "GET" "/_index_template/chatbot-template" "" "Verificación plantilla chatbot"
    
    # Crear índice de prueba que use plantilla scraper
    local scraper_test_doc='{
        "@timestamp": "2025-06-16T10:00:00Z",
        "source": "test",
        "url": "https://test.com",
        "title": "Documento de prueba scraper",
        "content": "Contenido de prueba para verificar plantilla",
        "status": "completed",
        "scraped_at": "2025-06-16T10:00:00Z",
        "processing_time": 1.5,
        "tags": ["test", "resilience"],
        "category": "testing"
    }'
    
    execute_query "POST" "/scraper-test-$(date +%Y%m%d)/_doc" "$scraper_test_doc" "Prueba de plantilla scraper"
    
    # Crear índice de prueba que use plantilla chatbot
    local chatbot_test_doc='{
        "@timestamp": "2025-06-16T10:00:00Z",
        "session_id": "test-session-001",
        "user_id": "test-user",
        "message": "¿Cuál es el estado del cluster?",
        "response": "El cluster está funcionando correctamente",
        "intent": "cluster_status",
        "confidence": 0.95,
        "processing_time": 0.3,
        "model_version": "v1.0",
        "conversation_turn": 1
    }'
    
    execute_query "POST" "/chatbot-test-$(date +%Y%m%d)/_doc" "$chatbot_test_doc" "Prueba de plantilla chatbot"
    
    # Verificar que los índices se crearon con la configuración correcta
    execute_query "GET" "/scraper-test-$(date +%Y%m%d)/_settings?pretty" "" "Configuración del índice scraper de prueba"
    execute_query "GET" "/chatbot-test-$(date +%Y%m%d)/_settings?pretty" "" "Configuración del índice chatbot de prueba"
}

# 9. MÉTRICAS DE RENDIMIENTO
performance_metrics() {
    print_header "MÉTRICAS DE RENDIMIENTO Y RECURSOS"
    
    # Estadísticas de nodos
    execute_query "GET" "/_nodes/stats?pretty" "" "Estadísticas detalladas de nodos"
    
    # Uso de memoria JVM
    execute_query "GET" "/_cat/nodes?v&h=name,heap.percent,heap.current,heap.max,ram.percent,ram.current,ram.max" "" "Uso de memoria por nodo"
    
    # Estadísticas de thread pools
    execute_query "GET" "/_cat/thread_pool?v&h=node_name,name,active,queue,rejected,completed" "" "Estado de thread pools"
    
    # Rendimiento de índices
    execute_query "GET" "/_stats/indexing,search,get?pretty" "" "Estadísticas de rendimiento"
    
    # Información de segmentos
    execute_query "GET" "/$INDEX/_segments?pretty" "" "Información de segmentos del índice"
}

# 10. REPORTE FINAL DE RESILIENCIA
generate_resilience_report() {
    print_header "REPORTE FINAL DE RESILIENCIA"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "\n${GREEN}📊 RESUMEN DE PRUEBAS DE RESILIENCIA${NC}"
    echo -e "${GREEN}Fecha/Hora: $timestamp${NC}"
    echo -e "${GREEN}Cluster: $HOST${NC}"
    echo -e "${GREEN}Índice Principal: $INDEX${NC}"
    
    # Estado final del cluster
    local cluster_health=$(curl -s -X GET "$HOST/_cluster/health" \
        -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
        --cacert "$CERT" \
        --connect-timeout 5 \
        --max-time "$TIMEOUT" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$cluster_health" ]; then
        local status=$(echo "$cluster_health" | jq -r '.status' 2>/dev/null)
        local nodes=$(echo "$cluster_health" | jq -r '.number_of_nodes' 2>/dev/null)
        local data_nodes=$(echo "$cluster_health" | jq -r '.number_of_data_nodes' 2>/dev/null)
        local active_shards=$(echo "$cluster_health" | jq -r '.active_shards' 2>/dev/null)
        local relocating_shards=$(echo "$cluster_health" | jq -r '.relocating_shards' 2>/dev/null)
        local unassigned_shards=$(echo "$cluster_health" | jq -r '.unassigned_shards' 2>/dev/null)
        
        echo -e "\n${CYAN}Estado Final del Cluster:${NC}"
        echo -e "Status: $status"
        echo -e "Nodos totales: $nodes"
        echo -e "Nodos de datos: $data_nodes"
        echo -e "Shards activos: $active_shards"
        echo -e "Shards reubicándose: $relocating_shards"
        echo -e "Shards no asignados: $unassigned_shards"
        
        if [ "$status" = "green" ]; then
            print_success "✅ CLUSTER EN ESTADO ÓPTIMO"
        elif [ "$status" = "yellow" ]; then
            print_warning "⚠️ CLUSTER CON ADVERTENCIAS"
        else
            print_error "❌ CLUSTER CON PROBLEMAS CRÍTICOS"
        fi
    fi
    
    echo -e "\n${CYAN}Recomendaciones para Monitoreo Continuo:${NC}"
    echo "1. Ejecutar estas consultas regularmente"
    echo "2. Configurar alertas en Kibana para métricas críticas"
    echo "3. Monitorear uso de heap y storage"
    echo "4. Realizar pruebas de fallo programadas"
    echo "5. Mantener backups actualizados"
}

# Función principal de ayuda
show_help() {
    echo "======================================================"
    echo "SCRIPT DE PRUEBAS DE RESILIENCIA - CLUSTER ELASTICSEARCH"
    echo "======================================================"
    echo ""
    echo "Uso: $0 [COMANDO]"
    echo ""
    echo "Comandos disponibles:"
    echo "  health          - Verificar salud general del cluster"
    echo "  index           - Estado específico del índice hoteles"
    echo "  shards          - Distribución de shards y réplicas"
    echo "  readwrite       - Pruebas de lectura/escritura"
    echo "  simulate        - Información sobre simulación de fallos"
    echo "  monitor         - Monitoreo durante fallo"
    echo "  recovery        - Verificación post-recuperación"
    echo "  templates       - Pruebas de plantillas de índice"
    echo "  performance     - Métricas de rendimiento"
    echo "  report          - Reporte final de resiliencia"
    echo "  all             - Ejecutar todas las pruebas"
    echo ""
    echo "Ejemplos:"
    echo "  $0 health       # Solo verificar salud del cluster"
    echo "  $0 all          # Ejecutar suite completa"
    echo "======================================================"
}

# Función principal
main() {
    print_header "INICIALIZANDO PRUEBAS DE RESILIENCIA"
    load_environment
    
    case "${1:-help}" in
        "health")
            check_cluster_health
            ;;
        "index")
            check_index_health
            ;;
        "shards")
            check_shard_distribution
            ;;
        "readwrite")
            test_read_write_operations
            ;;
        "simulate")
            simulate_node_failure_scenarios
            ;;
        "monitor")
            monitor_during_failure
            ;;
        "recovery")
            verify_post_recovery
            ;;
        "templates")
            test_index_templates
            ;;
        "performance")
            performance_metrics
            ;;
        "report")
            generate_resilience_report
            ;;
        "all")
            check_cluster_health
            check_index_health
            check_shard_distribution
            test_read_write_operations
            test_index_templates
            performance_metrics
            generate_resilience_report
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Ejecutar función principal con todos los argumentos
main "$@"
