#!/bin/bash

# Cambiar a la IP del host donde se ejecuta Elasticsearch (proyecto-vm1, vm2 o vm3)
HOST="${ELASTIC_HOSTS:-https://localhost:9200}"
# Ruta del certificado desde el filesystem compartido NFS
CERT="${CA_CERT:-/elk-share/certs/ca/ca.crt}"
# Indice
INDEX="hoteles"
# Timeout para consultas a Elasticsearch (en segundos)
TIMEOUT=10
# Variables de entorno de la pila
FILE_ENV="/home/docker/elk-ha/.env"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Definición de recursos
declare -A RESOURCES=(
    ["index:hoteles"]='hoteles'
    ["template:scraper"]='scraper-template'
    ["template:chatbot"]='chatbot-template'
)

# Función para imprimir con colores
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

print_usage() {
    echo ""
    echo "======================================================"
    echo "SINTAXIS:"
    echo "======================================================"
    echo "  $0 crear [tipo] [force]    - Crea recursos (índice y/o templates)"
    echo "  $0 test [tipo]             - Verifica existencia de recursos"
    echo "  $0 eliminar [tipo] [force] - Elimina recursos"
    echo "  $0 listar                  - Lista todas las plantillas existentes"
    echo ""
    echo "Tipos disponibles:"
    echo "  index        - Solo el índice 'hoteles'"
    echo "  templates    - Solo las plantillas scraper y chatbot"
    echo "  all          - Índice y plantillas (por defecto)"
    echo ""
    echo "Parámetro force:"
    echo "  force        - Fuerza la recreación de recursos existentes sin preguntar"
    echo "                 Si no se especifica, los recursos existentes se mantienen"
    echo ""
    echo "Ejemplos:"
    echo "  $0 crear                  # Crea índice y plantillas (mantiene existentes)"
    echo "  $0 crear index            # Solo crea el índice (mantiene si existe)"
    echo "  $0 crear templates force  # Recrea plantillas forzadamente"
    echo "  $0 crear all force        # Recrea todo forzadamente"
    echo "  $0 test all               # Verifica índice y plantillas"
    echo "  $0 eliminar templates     # Solo elimina plantillas"
    echo "======================================================"
    echo ""
}

# Función para verificar prerequisitos
check_prerequisites() {
    print_info "Verificando prerequisitos..."
    
    # Cargar variables de entorno desde .env si existe
    if [ -f "${FILE_ENV}" ]; then
        source ${FILE_ENV}
        print_success "Variables de entorno cargadas desde .env"
    else
        print_warning "Archivo .env no encontrado, usando variables del sistema"
    fi

    # Si la contraseña está vacía, abortar
    if [ -z "$ELASTIC_PASSWORD" ]; then
        print_error "Variable ELASTIC_PASSWORD vacía o no definida"
        print_info "💡 Asegúrate de que la variable esté definida en tu .env o como variable de entorno del sistema"
        exit 1
    fi

    # Verificar que el certificado existe
    if [ ! -f "$CERT" ]; then
        print_error "Certificado no encontrado en $CERT"
        print_info "💡 Verifica que el filesystem NFS esté montado correctamente"
        exit 1
    fi

    print_info "🔍 Verificando conectividad con Elasticsearch (timeout: ${TIMEOUT}s)..."
    # Verificar conectividad básica
    if ! curl -s --connect-timeout 5 --max-time "$TIMEOUT" --cacert "$CERT" "$HOST" > /dev/null; then
        print_error "No se puede conectar a Elasticsearch en $HOST"
        print_info "💡 Verifica que:"
        print_info "   - El servicio Elasticsearch esté ejecutándose"
        print_info "   - El puerto esté expuesto correctamente"
        print_info "   - La variable HOST tenga la IP/puerto correcto"
        exit 1
    fi

    print_success "Conectividad verificada"
}

# Función unificada para verificar existencia de recursos
verify_resources() {
    local resource_type="${1:-all}"
    local success_count=0
    local total_count=0
    
    print_info "🔍 Verificando existencia de recursos: $resource_type (timeout: ${TIMEOUT}s)..."
    
    case "$resource_type" in
        "index"|"all")
            total_count=$((total_count + 1))
            # Verificar índices
            INDEX_EXISTS=$(curl -s -w "%{http_code}" -o /dev/null -X HEAD "$HOST/$INDEX" \
                -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                --cacert "$CERT" \
                --connect-timeout 5 \
                --max-time "$TIMEOUT")

            if [ "$INDEX_EXISTS" = "200" ]; then
                print_success "El índice '$INDEX' EXISTE"
                success_count=$((success_count + 1))
                
                # Obtener información básica del índice
                INDEX_INFO=$(curl -s -X GET "$HOST/$INDEX/_stats" \
                    -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                    --cacert "$CERT" \
                    --connect-timeout 5 \
                    --max-time "$TIMEOUT" 2>/dev/null)
                
                if [ $? -eq 0 ] && [ -n "$INDEX_INFO" ]; then
                    TOTAL_DOCS=$(echo "$INDEX_INFO" | grep -o '"count":[0-9]*' | head -1 | cut -d':' -f2)
                    INDEX_SIZE=$(echo "$INDEX_INFO" | grep -o '"size_in_bytes":[0-9]*' | head -1 | cut -d':' -f2)
                    
                    if command -v bc >/dev/null 2>&1 && [ -n "$INDEX_SIZE" ] && [ "$INDEX_SIZE" != "" ]; then
                        INDEX_SIZE_MB=$(echo "scale=2; $INDEX_SIZE / 1024 / 1024" | bc 2>/dev/null)
                        print_info "📊 Documentos: ${TOTAL_DOCS:-0} | Tamaño: ${INDEX_SIZE_MB:-N/A} MB"
                    else
                        print_info "📊 Documentos: ${TOTAL_DOCS:-0} | Tamaño: ${INDEX_SIZE:-N/A} bytes"
                    fi
                fi
            elif [ "$INDEX_EXISTS" = "404" ]; then
                print_warning "El índice '$INDEX' NO EXISTE"
            else
                print_error "Error al verificar el índice (HTTP $INDEX_EXISTS)"
            fi
            ;;&
        "templates"|"all")
            # Verificar plantillas
            for template in "scraper-template" "chatbot-template"; do
                total_count=$((total_count + 1))
                TEMPLATE_EXISTS=$(curl -s -w "%{http_code}" -o /dev/null -X HEAD "$HOST/_index_template/$template" \
                    -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                    --cacert "$CERT" \
                    --connect-timeout 5 \
                    --max-time "$TIMEOUT")

                if [ "$TEMPLATE_EXISTS" = "200" ]; then
                    print_success "La plantilla '$template' EXISTE"
                    success_count=$((success_count + 1))
                elif [ "$TEMPLATE_EXISTS" = "404" ]; then
                    print_warning "La plantilla '$template' NO EXISTE"
                else
                    print_error "Error al verificar la plantilla '$template' (HTTP $TEMPLATE_EXISTS)"
                fi
            done
            ;;
    esac

    print_info "📊 Recursos encontrados: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        return 0
    else
        return 1
    fi
}

# Función unificada para crear recursos
create_resources() {
    local resource_type="${1:-all}"
    local force_recreate="${2:-false}"
    local creation_success=true
    
    print_info "🏗️  Creando recursos: $resource_type (force: $force_recreate)..."
    
    case "$resource_type" in
        "index"|"all")
            print_info "📋 Procesando índice '$INDEX'..."
            
            # Verificar si el índice ya existe
            INDEX_EXISTS=$(curl -s -w "%{http_code}" -o /dev/null -X HEAD "$HOST/$INDEX" \
                -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                --cacert "$CERT" \
                --connect-timeout 5 \
                --max-time "$TIMEOUT")

            if [ "$INDEX_EXISTS" = "200" ]; then
                if [ "$force_recreate" = "true" ]; then
                    print_warning "El índice '$INDEX' ya existe - FORZANDO RECREACIÓN"
                    print_info "🗑️  Eliminando índice existente (timeout: ${TIMEOUT}s)..."
                    DELETE_RESPONSE=$(curl -s -X DELETE "$HOST/$INDEX" \
                        -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                        --cacert "$CERT" \
                        --connect-timeout 5 \
                        --max-time "$TIMEOUT")
                    
                    if [ $? -eq 0 ] && echo "$DELETE_RESPONSE" | grep -q '"acknowledged":true'; then
                        print_success "Índice eliminado exitosamente"
                        INDEX_EXISTS="404"  # Marcar como no existente para proceder con la creación
                    else
                        print_error "Error al eliminar el índice"
                        creation_success=false
                    fi
                else
                    print_success "El índice '$INDEX' ya existe - MANTENIENDO EXISTENTE"
                    print_info "💡 Usa 'force' como tercer parámetro para forzar la recreación"
                fi
            fi

            # Crear índice solo si no existe o fue eliminado
            if [ "$creation_success" = true ] && [ "$INDEX_EXISTS" = "404" ]; then
                print_info "🏗️  Creando índice con mapping (timeout: ${TIMEOUT}s)..."
                CREATE_RESPONSE=$(curl -s -X PUT "$HOST/$INDEX" \
                    -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                    --cacert "$CERT" \
                    --connect-timeout 5 \
                    --max-time "$TIMEOUT" \
                    -H 'Content-Type: application/json' \
                    -d '{
                  "settings": {
                    "number_of_shards": 2,
                    "number_of_replicas": 1,
                    "index.write.wait_for_active_shards": 2
                  },
                  "mappings": {
                    "properties": {
                      "comentarios": { "type": "integer" },
                      "descripcion": { "type": "text" },
                      "destacados": { "type": "text" },
                      "direccion": { "type": "text" },
                      "fechaEntrada": { "type": "date", "format": "yyyy-MM-dd" },
                      "fechaSalida": { "type": "date", "format": "yyyy-MM-dd" },
                      "id": { "type": "keyword" },
                      "localidad": { "type": "text" },
                      "location": { "type": "geo_point" },
                      "marca": { "type": "text" },
                      "nombre": { "type": "text" },
                      "opinion": { "type": "float" },
                      "precio": { "type": "integer" },
                      "provincia": { "type": "text" },
                      "servicios": { "type": "text" },
                      "url": { "type": "keyword" }
                    }
                  }
                }')

                if [ $? -ne 0 ]; then
                    print_error "Timeout al crear el índice"
                    creation_success=false
                elif echo "$CREATE_RESPONSE" | grep -q '"acknowledged":true'; then
                    print_success "Índice '$INDEX' creado exitosamente"
                    sleep 2  # Esperar estabilización
                else
                    print_error "Falló la creación del índice: $CREATE_RESPONSE"
                    creation_success=false
                fi
            fi
            ;;&
        "templates"|"all")
            print_info "📋 Procesando plantillas de índices..."
            
            # Procesar plantilla scraper
            SCRAPER_EXISTS=$(curl -s -w "%{http_code}" -o /dev/null -X HEAD "$HOST/_index_template/scraper-template" \
                -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                --cacert "$CERT" \
                --connect-timeout 5 \
                --max-time "$TIMEOUT")

            if [ "$SCRAPER_EXISTS" = "200" ]; then
                if [ "$force_recreate" = "true" ]; then
                    print_warning "La plantilla 'scraper-template' ya existe - FORZANDO RECREACIÓN"
                    print_info "🏗️  Recreando plantilla scraper-template (timeout: ${TIMEOUT}s)..."
                    SCRAPER_RESPONSE=$(curl -s -X PUT "$HOST/_index_template/scraper-template" \
                        -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                        --cacert "$CERT" \
                        --connect-timeout 5 \
                        --max-time "$TIMEOUT" \
                        -H 'Content-Type: application/json' \
                        -d '{
                      "index_patterns": ["scraper-*"],
                      "priority": 100,
                      "template": {
                        "settings": {
                          "number_of_shards": 2,
                          "number_of_replicas": 1,
                          "index.write.wait_for_active_shards": 2,
                          "index.refresh_interval": "5s",
                          "index.max_result_window": 10000
                        },
                        "mappings": {
                          "properties": {
                            "@timestamp": { "type": "date" },
                            "source": { "type": "keyword" },
                            "url": { "type": "keyword" },
                            "title": { "type": "text", "analyzer": "standard" },
                            "content": { "type": "text", "analyzer": "standard" },
                            "metadata": { "type": "object" },
                            "status": { "type": "keyword" },
                            "scraped_at": { "type": "date" },
                            "processing_time": { "type": "float" },
                            "tags": { "type": "keyword" },
                            "category": { "type": "keyword" }
                          }
                        }
                      }
                    }')

                    if [ $? -ne 0 ]; then
                        print_error "Timeout al recrear plantilla scraper"
                        creation_success=false
                    elif echo "$SCRAPER_RESPONSE" | grep -q '"acknowledged":true'; then
                        print_success "Plantilla 'scraper-template' recreada exitosamente"
                    else
                        print_error "Error recreando plantilla scraper: $SCRAPER_RESPONSE"
                        creation_success=false
                    fi
                else
                    print_success "La plantilla 'scraper-template' ya existe - MANTENIENDO EXISTENTE"
                    print_info "💡 Usa 'force' como tercer parámetro para forzar la recreación"
                fi
            else
                # Crear plantilla scraper (no existe)
                print_info "🏗️  Creando plantilla scraper-template (timeout: ${TIMEOUT}s)..."
                SCRAPER_RESPONSE=$(curl -s -X PUT "$HOST/_index_template/scraper-template" \
                    -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                    --cacert "$CERT" \
                    --connect-timeout 5 \
                    --max-time "$TIMEOUT" \
                    -H 'Content-Type: application/json' \
                    -d '{
                  "index_patterns": ["scraper-*"],
                  "priority": 100,
                  "template": {
                    "settings": {
                      "number_of_shards": 2,
                      "number_of_replicas": 1,
                      "index.write.wait_for_active_shards": 2,
                      "index.refresh_interval": "5s",
                      "index.max_result_window": 10000
                    },
                    "mappings": {
                      "properties": {
                        "@timestamp": { "type": "date" },
                        "source": { "type": "keyword" },
                        "url": { "type": "keyword" },
                        "title": { "type": "text", "analyzer": "standard" },
                        "content": { "type": "text", "analyzer": "standard" },
                        "metadata": { "type": "object" },
                        "status": { "type": "keyword" },
                        "scraped_at": { "type": "date" },
                        "processing_time": { "type": "float" },
                        "tags": { "type": "keyword" },
                        "category": { "type": "keyword" }
                      }
                    }
                  }
                }')

                if [ $? -ne 0 ]; then
                    print_error "Timeout al crear plantilla scraper"
                    creation_success=false
                elif echo "$SCRAPER_RESPONSE" | grep -q '"acknowledged":true'; then
                    print_success "Plantilla 'scraper-template' creada exitosamente"
                else
                    print_error "Error creando plantilla scraper: $SCRAPER_RESPONSE"
                    creation_success=false
                fi
            fi

            # Procesar plantilla chatbot
            CHATBOT_EXISTS=$(curl -s -w "%{http_code}" -o /dev/null -X HEAD "$HOST/_index_template/chatbot-template" \
                -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                --cacert "$CERT" \
                --connect-timeout 5 \
                --max-time "$TIMEOUT")

            if [ "$CHATBOT_EXISTS" = "200" ]; then
                if [ "$force_recreate" = "true" ]; then
                    print_warning "La plantilla 'chatbot-template' ya existe - FORZANDO RECREACIÓN"
                    print_info "🏗️  Recreando plantilla chatbot-template (timeout: ${TIMEOUT}s)..."
                    CHATBOT_RESPONSE=$(curl -s -X PUT "$HOST/_index_template/chatbot-template" \
                        -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                        --cacert "$CERT" \
                        --connect-timeout 5 \
                        --max-time "$TIMEOUT" \
                        -H 'Content-Type: application/json' \
                        -d '{
                      "index_patterns": ["chatbot-*"],
                      "priority": 100,
                      "template": {
                        "settings": {
                          "number_of_shards": 2,
                          "number_of_replicas": 1,
                          "index.write.wait_for_active_shards": 2,
                          "index.refresh_interval": "5s",
                          "index.max_result_window": 10000
                        },
                        "mappings": {
                          "properties": {
                            "@timestamp": { "type": "date" },
                            "session_id": { "type": "keyword" },
                            "user_id": { "type": "keyword" },
                            "message": { "type": "text", "analyzer": "standard" },
                            "response": { "type": "text", "analyzer": "standard" },
                            "intent": { "type": "keyword" },
                            "confidence": { "type": "float" },
                            "processing_time": { "type": "float" },
                            "model_version": { "type": "keyword" },
                            "feedback": { "type": "keyword" },
                            "metadata": { "type": "object" },
                            "conversation_turn": { "type": "integer" }
                          }
                        }
                      }
                    }')

                    if [ $? -ne 0 ]; then
                        print_error "Timeout al recrear plantilla chatbot"
                        creation_success=false
                    elif echo "$CHATBOT_RESPONSE" | grep -q '"acknowledged":true'; then
                        print_success "Plantilla 'chatbot-template' recreada exitosamente"
                    else
                        print_error "Error recreando plantilla chatbot: $CHATBOT_RESPONSE"
                        creation_success=false
                    fi
                else
                    print_success "La plantilla 'chatbot-template' ya existe - MANTENIENDO EXISTENTE"
                    print_info "💡 Usa 'force' como tercer parámetro para forzar la recreación"
                fi
            else
                # Crear plantilla chatbot (no existe)
                print_info "🏗️  Creando plantilla chatbot-template (timeout: ${TIMEOUT}s)..."
                CHATBOT_RESPONSE=$(curl -s -X PUT "$HOST/_index_template/chatbot-template" \
                    -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                    --cacert "$CERT" \
                    --connect-timeout 5 \
                    --max-time "$TIMEOUT" \
                    -H 'Content-Type: application/json' \
                    -d '{
                  "index_patterns": ["chatbot-*"],
                  "priority": 100,
                  "template": {
                    "settings": {
                      "number_of_shards": 2,
                      "number_of_replicas": 1,
                      "index.write.wait_for_active_shards": 2,
                      "index.refresh_interval": "5s",
                      "index.max_result_window": 10000
                    },
                    "mappings": {
                      "properties": {
                        "@timestamp": { "type": "date" },
                        "session_id": { "type": "keyword" },
                        "user_id": { "type": "keyword" },
                        "message": { "type": "text", "analyzer": "standard" },
                        "response": { "type": "text", "analyzer": "standard" },
                        "intent": { "type": "keyword" },
                        "confidence": { "type": "float" },
                        "processing_time": { "type": "float" },
                        "model_version": { "type": "keyword" },
                        "feedback": { "type": "keyword" },
                        "metadata": { "type": "object" },
                        "conversation_turn": { "type": "integer" }
                      }
                    }
                  }
                }')

                if [ $? -ne 0 ]; then
                    print_error "Timeout al crear plantilla chatbot"
                    creation_success=false
                elif echo "$CHATBOT_RESPONSE" | grep -q '"acknowledged":true'; then
                    print_success "Plantilla 'chatbot-template' creada exitosamente"
                else
                    print_error "Error creando plantilla chatbot: $CHATBOT_RESPONSE"
                    creation_success=false
                fi
            fi
            ;;
    esac

    if [ "$creation_success" = true ]; then
        return 0
    else
        return 1
    fi
}

# Función unificada para eliminar recursos
delete_resources() {
    local resource_type="${1:-all}"
    local force_delete="${2:-false}"
    local deletion_success=true
    
    print_warning "Eliminando recursos: $resource_type"
    
    if [ "$force_delete" = "true" ]; then
        print_warning "MODO FORZADO: Eliminación sin confirmación"
    else
        print_warning "Esta operación es irreversible"
        read -p "¿Estás seguro? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            print_info "Operación cancelada"
            return 0
        fi
    fi
    
    print_info "🗑️  Eliminando recursos: $resource_type..."
    
    case "$resource_type" in
        "index"|"all")
            print_info "🗑️  Eliminando índice '$INDEX' (timeout: ${TIMEOUT}s)..."
            DELETE_INDEX_RESPONSE=$(curl -s -X DELETE "$HOST/$INDEX" \
                -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                --cacert "$CERT" \
                --connect-timeout 5 \
                --max-time "$TIMEOUT")
            
            if [ $? -eq 0 ] && echo "$DELETE_INDEX_RESPONSE" | grep -q '"acknowledged":true'; then
                print_success "Índice '$INDEX' eliminado exitosamente"
            elif [ $? -ne 0 ]; then
                print_error "Timeout al eliminar el índice"
                deletion_success=false
            else
                print_warning "Respuesta eliminación índice: $DELETE_INDEX_RESPONSE"
            fi
            ;;&
        "templates"|"all")
            # Eliminar plantillas
            for template in "scraper-template" "chatbot-template"; do
                print_info "🗑️  Eliminando plantilla '$template' (timeout: ${TIMEOUT}s)..."
                DELETE_TEMPLATE_RESPONSE=$(curl -s -X DELETE "$HOST/_index_template/$template" \
                    -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                    --cacert "$CERT" \
                    --connect-timeout 5 \
                    --max-time "$TIMEOUT")

                if [ $? -eq 0 ] && echo "$DELETE_TEMPLATE_RESPONSE" | grep -q '"acknowledged":true'; then
                    print_success "Plantilla '$template' eliminada exitosamente"
                elif [ $? -ne 0 ]; then
                    print_error "Timeout al eliminar plantilla '$template'"
                    deletion_success=false
                else
                    print_warning "Respuesta eliminación '$template': $DELETE_TEMPLATE_RESPONSE"
                fi
            done
            ;;
    esac

    if [ "$deletion_success" = true ]; then
        return 0
    else
        return 1
    fi
}

# Función para listar plantillas
list_templates() {
    print_info "📋 Listando todas las plantillas de índices (timeout: ${TIMEOUT}s)..."
    
    TEMPLATES_RESPONSE=$(curl -s -X GET "$HOST/_index_template" \
        -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
        --cacert "$CERT" \
        --connect-timeout 5 \
        --max-time "$TIMEOUT")

    if [ $? -ne 0 ]; then
        print_error "Timeout al obtener las plantillas"
        return 1
    elif [ -n "$TEMPLATES_RESPONSE" ]; then
        print_info "🔍 Plantillas encontradas:"
        
        TEMPLATE_NAMES=$(echo "$TEMPLATES_RESPONSE" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
        
        if [ -n "$TEMPLATE_NAMES" ]; then
            echo "$TEMPLATE_NAMES" | while read -r template_name; do
                if [ -n "$template_name" ]; then
                    if [[ "$template_name" == "scraper-template" || "$template_name" == "chatbot-template" ]]; then
                        print_success "  ✓ $template_name (gestionada por este script)"
                    else
                        print_info "  • $template_name"
                    fi
                fi
            done
        else
            print_warning "No se encontraron plantillas"
        fi
        return 0
    else
        print_error "No se pudo obtener la lista de plantillas"
        return 1
    fi
}

# Verificar parámetros
if [ $# -eq 0 ]; then
    print_error "Falta el parámetro requerido"
    print_usage
    exit 1
fi

COMMAND="$1"
RESOURCE_TYPE="${2:-all}"
FORCE_PARAM="${3:-}"

# Validar tipo de recurso
if [ "$RESOURCE_TYPE" != "index" ] && [ "$RESOURCE_TYPE" != "templates" ] && [ "$RESOURCE_TYPE" != "all" ]; then
    # Verificar si el segundo parámetro es 'force' y el tipo se omitió
    if [ "$RESOURCE_TYPE" = "force" ]; then
        RESOURCE_TYPE="all"
        FORCE_PARAM="force"
    else
        print_error "Tipo de recurso inválido: '$RESOURCE_TYPE'"
        print_usage
        exit 1
    fi
fi

# Validar parámetro force
FORCE_MODE="false"
if [ "$FORCE_PARAM" = "force" ]; then
    FORCE_MODE="true"
elif [ -n "$FORCE_PARAM" ] && [ "$FORCE_PARAM" != "force" ]; then
    print_error "Parámetro inválido: '$FORCE_PARAM'. Solo se acepta 'force'"
    print_usage
    exit 1
fi

# Procesar comandos
case "$COMMAND" in
    "crear")
        echo "======================================================"
        print_info "MODO: CREAR RECURSOS ($RESOURCE_TYPE) - Force: $FORCE_MODE"
        echo "======================================================"
        check_prerequisites
        if create_resources "$RESOURCE_TYPE" "$FORCE_MODE"; then
            echo "======================================================"
            print_success "🎉 Creación completada exitosamente"
            case "$RESOURCE_TYPE" in
                "templates")
                    print_info "Las plantillas aplicarán automáticamente a:"
                    print_info "  • scraper-* → 2 shard, 1 réplicas"
                    print_info "  • chatbot-* → 2 shard, 1 réplicas"
                    ;;
                "all")
                    print_info "Índice creado y plantillas configuradas"
                    ;;
            esac
            if [ "$FORCE_MODE" = "true" ]; then
                print_info "✓ Recursos recreados forzadamente"
            else
                print_info "✓ Recursos existentes mantenidos"
            fi
            echo "======================================================"
            exit 0
        else
            echo "======================================================"
            print_error "💥 Error en la creación de recursos"
            echo "======================================================"
            exit 1
        fi
        ;;
    "test")
        echo "======================================================"
        print_info "MODO: VERIFICAR RECURSOS ($RESOURCE_TYPE)"
        echo "======================================================"
        check_prerequisites
        if verify_resources "$RESOURCE_TYPE"; then
            echo "======================================================"
            print_success "🎉 Todos los recursos verificados exitosamente"
            echo "======================================================"
            exit 0
        else
            echo "======================================================"
            print_warning "Algunos recursos no existen o hay problemas"
            echo "======================================================"
            exit 1
        fi
        ;;
    "eliminar")
        echo "======================================================"
        print_info "MODO: ELIMINAR RECURSOS ($RESOURCE_TYPE) - Force: $FORCE_MODE"
        echo "======================================================"
        check_prerequisites
        if delete_resources "$RESOURCE_TYPE" "$FORCE_MODE"; then
            echo "======================================================"
            print_success "🎉 Eliminación completada exitosamente"
            echo "======================================================"
            exit 0
        else
            echo "======================================================"
            print_error "💥 Error en la eliminación de recursos"
            echo "======================================================"
            exit 1
        fi
        ;;
    "listar")
        echo "======================================================"
        print_info "MODO: LISTAR PLANTILLAS"
        echo "======================================================"
        check_prerequisites
        if list_templates; then
            echo "======================================================"
            print_success "🎉 Listado completado"
            echo "======================================================"
            exit 0
        else
            echo "======================================================"
            print_error "💥 Error al listar plantillas"
            echo "======================================================"
            exit 1
        fi
        ;;
    *)
        print_error "Comando inválido: '$COMMAND'"
        print_usage
        exit 1
        ;;
esac
