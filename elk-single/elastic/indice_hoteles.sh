#!/bin/bash

# Cambiar a la IP del host donde se ejecuta Elasticsearch (proyecto-vm1, vm2 o vm3)
HOST="${ELASTIC_HOSTS:-https://localhost:9200}"
# Ruta del certificado desde el filesystem compartido NFS
CERT="${CA_CERT:-/elk-single/certs/ca/ca.crt}"
# Indice
INDEX="hoteles"
# Timeout para consultas a Elasticsearch (en segundos)
TIMEOUT=10
# Variables de entorno de la pila
FILE_ENV="/home/docker/elk-single/.env"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo "  $0 crear    - Crea el índice 'hoteles' con su mapping"
    echo "  $0 test     - Verifica si el índice 'hoteles' existe"
    echo ""
    echo "Ejemplos:"
    echo "  $0 crear"
    echo "  $0 test"
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
    # print_info "Donde estoy: $PWD"
    # print_info "USER: $ELASTIC_USER"
    # print_info "PASSWORD: $ELASTIC_PASSWORD"
    # print_info "CERT_PATH: $CERT"
    # print_info "HOST: $HOST"
    # print_info "INDEX: $INDEX"
    # print_info "TIMEOUT: ${TIMEOUT}s"
}

# Función para verificar si el índice existe
test_index() {
    print_info "🔍 Verificando existencia del índice '$INDEX' (timeout: ${TIMEOUT}s)..."
    
    INDEX_EXISTS=$(curl -s -w "%{http_code}" -o /dev/null -X HEAD "$HOST/$INDEX" \
        -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
        --cacert "$CERT" \
        --connect-timeout 5 \
        --max-time "$TIMEOUT")

    if [ "$INDEX_EXISTS" = "200" ]; then
        print_success "El índice '$INDEX' EXISTE"
        
        # Obtener información básica del índice con timeout
        print_info "Obteniendo información del índice (timeout: ${TIMEOUT}s)..."
        INDEX_INFO=$(curl -s -X GET "$HOST/$INDEX/_stats" \
            -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
            --cacert "$CERT" \
            --connect-timeout 5 \
            --max-time "$TIMEOUT" 2>/dev/null)
        
        # Verificar si la consulta fue exitosa
        if [ $? -eq 0 ] && [ -n "$INDEX_INFO" ]; then
            TOTAL_DOCS=$(echo "$INDEX_INFO" | grep -o '"count":[0-9]*' | head -1 | cut -d':' -f2)
            INDEX_SIZE=$(echo "$INDEX_INFO" | grep -o '"size_in_bytes":[0-9]*' | head -1 | cut -d':' -f2)
            
            if command -v bc >/dev/null 2>&1 && [ -n "$INDEX_SIZE" ] && [ "$INDEX_SIZE" != "" ]; then
                INDEX_SIZE_MB=$(echo "scale=2; $INDEX_SIZE / 1024 / 1024" | bc 2>/dev/null)
                print_info "📊 Documentos: ${TOTAL_DOCS:-0}"
                print_info "💾 Tamaño: ${INDEX_SIZE_MB:-N/A} MB"
            else
                print_info "📊 Documentos: ${TOTAL_DOCS:-0}"
                print_info "💾 Tamaño: ${INDEX_SIZE:-N/A} bytes"
            fi
        else
            print_warning "Timeout o error al obtener estadísticas del índice"
            print_info "💡 El índice existe pero no se pudieron obtener las estadísticas (posible timeout)"
        fi
        
        return 0
    elif [ "$INDEX_EXISTS" = "404" ]; then
        print_warning "El índice '$INDEX' NO EXISTE"
        return 1
    elif [ "$INDEX_EXISTS" = "000" ]; then
        print_error "Timeout o error de conexión al verificar la existencia del índice"
        print_info "💡 Considera aumentar el valor de TIMEOUT (actualmente ${TIMEOUT}s)"
        return 2
    else
        print_error "Error al verificar la existencia del índice (HTTP $INDEX_EXISTS)"
        return 2
    fi
}

# Función para crear el índice
create_index() {
    print_info "🏗️  Creando índice '$INDEX'..."
    
    # Verificar si el índice ya existe
    if test_index > /dev/null 2>&1; then
        print_warning "El índice '$INDEX' ya existe"
        read -p "¿Deseas eliminarlo y recrearlo? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            print_info "Operación cancelada"
            exit 0
        fi
        
        print_info "🗑️  Eliminando índice existente (timeout: ${TIMEOUT}s)..."
        DELETE_RESPONSE=$(curl -s -X DELETE "$HOST/$INDEX" \
            -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
            --cacert "$CERT" \
            --connect-timeout 5 \
            --max-time "$TIMEOUT")
        
        if [ $? -eq 0 ] && echo "$DELETE_RESPONSE" | grep -q '"acknowledged":true'; then
            print_success "Índice eliminado exitosamente"
        elif [ $? -ne 0 ]; then
            print_error "Timeout al eliminar el índice"
            print_info "💡 Considera aumentar el valor de TIMEOUT (actualmente ${TIMEOUT}s)"
            return 1
        else
            print_warning "Respuesta de eliminación: $DELETE_RESPONSE"
        fi
    fi

    print_info "🏗️  Creando nuevo índice con mapping (timeout: ${TIMEOUT}s)..."
    # Crear índice con mapping
        # Cluster varios nodos
        # "number_of_shards": 2,
        # "number_of_replicas": 1,
        # "index.write.wait_for_active_shards": 2
    CREATE_RESPONSE=$(curl -s -X PUT "$HOST/$INDEX" \
        -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
        --cacert "$CERT" \
        --connect-timeout 5 \
        --max-time "$TIMEOUT" \
        -H 'Content-Type: application/json' \
        -d '{
      "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 0,
        "index.write.wait_for_active_shards": 1
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

    # Verificar si la creación fue exitosa
    if [ $? -ne 0 ]; then
        print_error "Timeout al crear el índice"
        print_info "💡 Considera aumentar el valor de TIMEOUT (actualmente ${TIMEOUT}s)"
        return 1
    elif echo "$CREATE_RESPONSE" | grep -q '"acknowledged":true'; then
        print_success "Índice '$INDEX' creado exitosamente"
        
        # Esperar un momento para que el índice esté disponible
        sleep 2
        
        print_info "🔍 Verificando estado del índice (timeout: ${TIMEOUT}s)..."
        # Verificar el estado del índice
        INDEX_HEALTH=$(curl -s -X GET "$HOST/_cluster/health/$INDEX" \
            -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
            --cacert "$CERT" \
            --connect-timeout 5 \
            --max-time "$TIMEOUT")
        
        if [ $? -eq 0 ] && [ -n "$INDEX_HEALTH" ]; then
            STATUS=$(echo "$INDEX_HEALTH" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
            SHARDS=$(echo "$INDEX_HEALTH" | grep -o '"active_shards":[0-9]*' | cut -d':' -f2)
            
            print_info "📊 Estado: ${STATUS:-unknown}"
            print_info "🔧 Shards activos: ${SHARDS:-unknown}"
            
            if [ "$STATUS" = "green" ] || [ "$STATUS" = "yellow" ]; then
                print_success "Configuración del índice verificada"
            else
                print_warning "El índice puede no estar completamente listo"
            fi
        else
            print_warning "Timeout o error al verificar el estado del índice"
            print_info "💡 El índice fue creado pero no se pudo verificar su estado"
        fi
        
        return 0
    else
        print_error "Falló la creación del índice"
        print_error "Respuesta completa: $CREATE_RESPONSE"
        return 1
    fi
}

# Verificar que se ha proporcionado un parámetro
if [ $# -eq 0 ]; then
    print_error "Falta el parámetro requerido"
    print_usage
    exit 1
fi

# Procesar el parámetro
case "$1" in
    "crear")
        echo "======================================================"
        print_info "MODO: CREAR ÍNDICE"
        echo "======================================================"
        check_prerequisites
        if create_index; then
            echo "======================================================"
            print_success "🎉 Proceso de creación completado exitosamente"
            echo "======================================================"
            exit 0
        else
            echo "======================================================"
            print_error "💥 Error en la creación del índice"
            echo "======================================================"
            exit 1
        fi
        ;;
    "test")
        echo "======================================================"
        print_info "MODO: TEST DE EXISTENCIA"
        echo "======================================================"
        check_prerequisites
        if test_index; then
            echo "======================================================"
            print_success "🎉 Test completado - Índice existe y está operativo"
            echo "======================================================"
            exit 0
        else
            echo "======================================================"
            print_warning "Test completado - Índice no existe o hay problemas"
            echo "======================================================"
            exit 1
        fi
        ;;
    *)
        print_error "Parámetro inválido: '$1'"
        print_usage
        exit 1
        ;;
esac