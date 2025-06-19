#!/bin/bash

# Cambiar a la IP del host donde se ejecuta Elasticsearch (proyecto-vm1, vm2 o vm3)
HOST="${ELASTIC_HOSTS:-https://localhost:9200}"
# Ruta del certificado desde el filesystem compartido NFS
CERT="${CA_CERT:-/elk-share/certs/ca/ca.crt}"
# Timeout para consultas a Elasticsearch (en segundos)
TIMEOUT=10
# Variables de entorno de la pila
FILE_ENV="/home/docker/elk-ha/.env"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuración de usuarios y roles
declare -A USERS=(
    ["metricbeat_internal"]="Usuario interno para Metricbeat"
    ["monitoring_admin"]="Usuario para acceso web al Stack Monitoring"
)

declare -A ROLES=(
    ["metricbeat_writer"]="Rol personalizado para escritura de métricas"
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

print_header() {
    echo -e "${PURPLE}🔐 $1${NC}"
}

print_usage() {
    echo ""
    echo "======================================================"
    echo "SINTAXIS:"
    echo "======================================================"
    echo "  $0 crear [tipo] [force]    - Crea usuarios y roles para Metricbeat"
    echo "  $0 test [tipo]             - Verifica existencia de usuarios/roles"
    echo "  $0 eliminar [tipo] [force] - Elimina usuarios y roles"
    echo "  $0 listar                  - Lista usuarios y roles existentes"
    echo ""
    echo "Tipos disponibles:"
    echo "  users        - Solo usuarios (metricbeat_internal, monitoring_admin)"
    echo "  roles        - Solo roles (metricbeat_writer)"
    echo "  all          - Usuarios y roles (por defecto)"
    echo ""
    echo "Parámetro force:"
    echo "  force        - Fuerza la recreación de recursos existentes sin preguntar"
    echo "                 Si no se especifica, los recursos existentes se mantienen"
    echo ""
    echo "Ejemplos:"
    echo "  $0 crear                  # Crea usuarios y roles (mantiene existentes)"
    echo "  $0 crear users            # Solo crea usuarios (mantiene si existen)"
    echo "  $0 crear roles force      # Recrea roles forzadamente"
    echo "  $0 crear all force        # Recrea todo forzadamente"
    echo "  $0 test all               # Verifica usuarios y roles"
    echo "  $0 eliminar users         # Solo elimina usuarios"
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

# Función para verificar existencia de roles
verify_roles() {
    local success_count=0
    local total_count=0
    
    print_header "Verificando roles de seguridad..."
    
    for role_name in "${!ROLES[@]}"; do
        total_count=$((total_count + 1))
        print_info "🔍 Verificando rol '$role_name'..."
        
        ROLE_EXISTS=$(curl -s -w "%{http_code}" -o /dev/null -X GET "$HOST/_security/role/$role_name" \
            -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
            --cacert "$CERT" \
            --connect-timeout 5 \
            --max-time "$TIMEOUT")

        if [ "$ROLE_EXISTS" = "200" ]; then
            print_success "El rol '$role_name' EXISTE"
            print_info "📋 ${ROLES[$role_name]}"
            success_count=$((success_count + 1))
        elif [ "$ROLE_EXISTS" = "404" ]; then
            print_warning "El rol '$role_name' NO EXISTE"
        else
            print_error "Error al verificar el rol '$role_name' (HTTP $ROLE_EXISTS)"
        fi
    done
    
    print_info "📊 Roles encontrados: $success_count/$total_count"
    return $success_count
}

# Función para verificar existencia de usuarios
verify_users() {
    local success_count=0
    local total_count=0
    
    print_header "Verificando usuarios de seguridad..."
    
    for user_name in "${!USERS[@]}"; do
        total_count=$((total_count + 1))
        print_info "🔍 Verificando usuario '$user_name'..."
        
        USER_EXISTS=$(curl -s -w "%{http_code}" -o /dev/null -X GET "$HOST/_security/user/$user_name" \
            -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
            --cacert "$CERT" \
            --connect-timeout 5 \
            --max-time "$TIMEOUT")

        if [ "$USER_EXISTS" = "200" ]; then
            print_success "El usuario '$user_name' EXISTE"
            print_info "👤 ${USERS[$user_name]}"
            
            # Obtener información adicional del usuario
            USER_INFO=$(curl -s -X GET "$HOST/_security/user/$user_name" \
                -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                --cacert "$CERT" \
                --connect-timeout 5 \
                --max-time "$TIMEOUT" 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$USER_INFO" ]; then
                USER_ROLES=$(echo "$USER_INFO" | grep -o '"roles":\[[^]]*\]' | sed 's/"roles":\[//;s/\]//;s/"//g')
                if [ -n "$USER_ROLES" ]; then
                    print_info "🏷️  Roles asignados: $USER_ROLES"
                fi
            fi
            success_count=$((success_count + 1))
        elif [ "$USER_EXISTS" = "404" ]; then
            print_warning "El usuario '$user_name' NO EXISTE"
        else
            print_error "Error al verificar el usuario '$user_name' (HTTP $USER_EXISTS)"
        fi
    done
    
    print_info "📊 Usuarios encontrados: $success_count/$total_count"
    return $success_count
}

# Función unificada para verificar existencia de recursos
verify_resources() {
    local resource_type="${1:-all}"
    local roles_success=0
    local users_success=0
    local total_success=0
    
    print_info "🔍 Verificando existencia de recursos: $resource_type (timeout: ${TIMEOUT}s)..."
    
    case "$resource_type" in
        "roles"|"all")
            verify_roles
            roles_success=$?
            ;;&
        "users"|"all")
            verify_users
            users_success=$?
            ;;&
    esac

    case "$resource_type" in
        "roles")
            total_success=$roles_success
            ;;
        "users")
            total_success=$users_success
            ;;
        "all")
            total_success=$((roles_success + users_success))
            ;;
    esac

    if [ $total_success -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# Función para crear roles
create_roles() {
    local force_recreate="${1:-false}"
    local creation_success=true
    
    print_header "Creando roles de seguridad..."
    
    # Crear rol metricbeat_writer
    print_info "📋 Procesando rol 'metricbeat_writer'..."
    
    ROLE_EXISTS=$(curl -s -w "%{http_code}" -o /dev/null -X GET "$HOST/_security/role/metricbeat_writer" \
        -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
        --cacert "$CERT" \
        --connect-timeout 5 \
        --max-time "$TIMEOUT")

    if [ "$ROLE_EXISTS" = "200" ]; then
        if [ "$force_recreate" = "true" ]; then
            print_warning "El rol 'metricbeat_writer' ya existe - FORZANDO RECREACIÓN"
        else
            print_success "El rol 'metricbeat_writer' ya existe - MANTENIENDO EXISTENTE"
            print_info "💡 Usa 'force' como tercer parámetro para forzar la recreación"
            return 0
        fi
    fi

    if [ "$force_recreate" = "true" ] || [ "$ROLE_EXISTS" != "200" ]; then
        print_info "🏗️  Creando rol 'metricbeat_writer' (timeout: ${TIMEOUT}s)..."
        ROLE_RESPONSE=$(curl -s -X PUT "$HOST/_security/role/metricbeat_writer" \
            -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
            --cacert "$CERT" \
            --connect-timeout 5 \
            --max-time "$TIMEOUT" \
            -H 'Content-Type: application/json' \
            -d '{
              "cluster": ["monitor", "read_ilm", "read_slm"],
              "indices": [
                {
                  "names": ["metricbeat-*", ".monitoring-beats-*"],
                  "privileges": ["write", "create_index", "view_index_metadata", "create_doc"]
                }
              ]
            }')

        if [ $? -ne 0 ]; then
            print_error "Timeout al crear el rol 'metricbeat_writer'"
            creation_success=false
        elif echo "$ROLE_RESPONSE" | grep -q '"created":true\|"role":'; then
            print_success "Rol 'metricbeat_writer' creado exitosamente"
            print_info "🔑 Permisos: monitor cluster, escritura en índices metricbeat-*"
        else
            print_error "Error creando rol 'metricbeat_writer': $ROLE_RESPONSE"
            creation_success=false
        fi
    fi

    if [ "$creation_success" = true ]; then
        return 0
    else
        return 1
    fi
}

# Función para crear usuarios
create_users() {
    local force_recreate="${1:-false}"
    local creation_success=true
    
    print_header "Creando usuarios de seguridad..."
    
    # Crear usuario metricbeat_internal
    print_info "👤 Procesando usuario 'metricbeat_internal'..."
    
    USER_EXISTS=$(curl -s -w "%{http_code}" -o /dev/null -X GET "$HOST/_security/user/metricbeat_internal" \
        -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
        --cacert "$CERT" \
        --connect-timeout 5 \
        --max-time "$TIMEOUT")

    if [ "$USER_EXISTS" = "200" ]; then
        if [ "$force_recreate" = "true" ]; then
            print_warning "El usuario 'metricbeat_internal' ya existe - FORZANDO RECREACIÓN"
        else
            print_success "El usuario 'metricbeat_internal' ya existe - MANTENIENDO EXISTENTE"
        fi
    fi

    if [ "$force_recreate" = "true" ] || [ "$USER_EXISTS" != "200" ]; then
        print_info "🏗️  Creando usuario 'metricbeat_internal' (timeout: ${TIMEOUT}s)..."
        USER_RESPONSE=$(curl -s -X POST "$HOST/_security/user/metricbeat_internal" \
            -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
            --cacert "$CERT" \
            --connect-timeout 5 \
            --max-time "$TIMEOUT" \
            -H 'Content-Type: application/json' \
            -d "{
              \"password\": \"${ELASTIC_PASSWORD}\",
              \"roles\": [\"metricbeat_writer\", \"beats_system\"],
              \"full_name\": \"Internal Metricbeat User\",
              \"email\": \"metricbeat@example.com\"
            }")

        if [ $? -ne 0 ]; then
            print_error "Timeout al crear el usuario 'metricbeat_internal'"
            creation_success=false
        elif echo "$USER_RESPONSE" | grep -q '"created":true\|"user":'; then
            print_success "Usuario 'metricbeat_internal' creado exitosamente"
            print_info "🏷️  Roles: metricbeat_writer, beats_system"
        else
            print_error "Error creando usuario 'metricbeat_internal': $USER_RESPONSE"
            creation_success=false
        fi
    fi

    # Crear usuario monitoring_admin
    print_info "👤 Procesando usuario 'monitoring_admin'..."
    
    ADMIN_EXISTS=$(curl -s -w "%{http_code}" -o /dev/null -X GET "$HOST/_security/user/monitoring_admin" \
        -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
        --cacert "$CERT" \
        --connect-timeout 5 \
        --max-time "$TIMEOUT")

    if [ "$ADMIN_EXISTS" = "200" ]; then
        if [ "$force_recreate" = "true" ]; then
            print_warning "El usuario 'monitoring_admin' ya existe - FORZANDO RECREACIÓN"
        else
            print_success "El usuario 'monitoring_admin' ya existe - MANTENIENDO EXISTENTE"
        fi
    fi

    if [ "$force_recreate" = "true" ] || [ "$ADMIN_EXISTS" != "200" ]; then
        print_info "🏗️  Creando usuario 'monitoring_admin' (timeout: ${TIMEOUT}s)..."
        ADMIN_RESPONSE=$(curl -s -X POST "$HOST/_security/user/monitoring_admin" \
            -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
            --cacert "$CERT" \
            --connect-timeout 5 \
            --max-time "$TIMEOUT" \
            -H 'Content-Type: application/json' \
            -d "{
              \"password\": \"${ELASTIC_PASSWORD}\",
              \"roles\": [\"monitoring_user\", \"kibana_admin\", \"superuser\"],
              \"full_name\": \"Monitoring Administrator\",
              \"email\": \"monitoring@example.com\"
            }")

        if [ $? -ne 0 ]; then
            print_error "Timeout al crear el usuario 'monitoring_admin'"
            creation_success=false
        elif echo "$ADMIN_RESPONSE" | grep -q '"created":true\|"user":'; then
            print_success "Usuario 'monitoring_admin' creado exitosamente"
            print_info "🏷️  Roles: monitoring_user, kibana_admin, superuser"
        else
            print_error "Error creando usuario 'monitoring_admin': $ADMIN_RESPONSE"
            creation_success=false
        fi
    fi

    if [ "$creation_success" = true ]; then
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
        "roles"|"all")
            if ! create_roles "$force_recreate"; then
                creation_success=false
            fi
            ;;&
        "users"|"all")
            if ! create_users "$force_recreate"; then
                creation_success=false
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
        "users"|"all")
            # Eliminar usuarios
            for user_name in "${!USERS[@]}"; do
                print_info "🗑️  Eliminando usuario '$user_name' (timeout: ${TIMEOUT}s)..."
                DELETE_USER_RESPONSE=$(curl -s -X DELETE "$HOST/_security/user/$user_name" \
                    -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                    --cacert "$CERT" \
                    --connect-timeout 5 \
                    --max-time "$TIMEOUT")

                if [ $? -eq 0 ] && echo "$DELETE_USER_RESPONSE" | grep -q '"found":true'; then
                    print_success "Usuario '$user_name' eliminado exitosamente"
                elif [ $? -ne 0 ]; then
                    print_error "Timeout al eliminar usuario '$user_name'"
                    deletion_success=false
                else
                    print_warning "Respuesta eliminación '$user_name': $DELETE_USER_RESPONSE"
                fi
            done
            ;;&
        "roles"|"all")
            # Eliminar roles
            for role_name in "${!ROLES[@]}"; do
                print_info "🗑️  Eliminando rol '$role_name' (timeout: ${TIMEOUT}s)..."
                DELETE_ROLE_RESPONSE=$(curl -s -X DELETE "$HOST/_security/role/$role_name" \
                    -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
                    --cacert "$CERT" \
                    --connect-timeout 5 \
                    --max-time "$TIMEOUT")

                if [ $? -eq 0 ] && echo "$DELETE_ROLE_RESPONSE" | grep -q '"found":true'; then
                    print_success "Rol '$role_name' eliminado exitosamente"
                elif [ $? -ne 0 ]; then
                    print_error "Timeout al eliminar rol '$role_name'"
                    deletion_success=false
                else
                    print_warning "Respuesta eliminación '$role_name': $DELETE_ROLE_RESPONSE"
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

# Función para listar usuarios y roles
list_resources() {
    print_header "Listando usuarios y roles de seguridad..."
    
    # Listar usuarios
    print_info "👥 Listando usuarios (timeout: ${TIMEOUT}s)..."
    USERS_RESPONSE=$(curl -s -X GET "$HOST/_security/user" \
        -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
        --cacert "$CERT" \
        --connect-timeout 5 \
        --max-time "$TIMEOUT")

    if [ $? -ne 0 ]; then
        print_error "Timeout al obtener usuarios"
    elif [ -n "$USERS_RESPONSE" ]; then
        USER_NAMES=$(echo "$USERS_RESPONSE" | grep -o '"[^"]*":' | sed 's/"//g;s"://' | grep -v '^$')
        
        if [ -n "$USER_NAMES" ]; then
            echo "$USER_NAMES" | while read -r user_name; do
                if [ -n "$user_name" ]; then
                    if [[ "$user_name" == "metricbeat_internal" || "$user_name" == "monitoring_admin" ]]; then
                        print_success "  ✓ $user_name (gestionado por este script)"
                    else
                        print_info "  • $user_name"
                    fi
                fi
            done
        else
            print_warning "No se encontraron usuarios"
        fi
    fi

    # Listar roles
    print_info "🏷️  Listando roles (timeout: ${TIMEOUT}s)..."
    ROLES_RESPONSE=$(curl -s -X GET "$HOST/_security/role" \
        -u "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
        --cacert "$CERT" \
        --connect-timeout 5 \
        --max-time "$TIMEOUT")

    if [ $? -ne 0 ]; then
        print_error "Timeout al obtener roles"
        return 1
    elif [ -n "$ROLES_RESPONSE" ]; then
        ROLE_NAMES=$(echo "$ROLES_RESPONSE" | grep -o '"[^"]*":' | sed 's/"//g;s"://' | grep -v '^$')
        
        if [ -n "$ROLE_NAMES" ]; then
            echo "$ROLE_NAMES" | while read -r role_name; do
                if [ -n "$role_name" ]; then
                    if [[ "$role_name" == "metricbeat_writer" ]]; then
                        print_success "  ✓ $role_name (gestionado por este script)"
                    else
                        print_info "  • $role_name"
                    fi
                fi
            done
        else
            print_warning "No se encontraron roles"
        fi
        return 0
    else
        print_error "No se pudo obtener la lista de roles"
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
if [ "$RESOURCE_TYPE" != "users" ] && [ "$RESOURCE_TYPE" != "roles" ] && [ "$RESOURCE_TYPE" != "all" ]; then
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
        print_info "MODO: CREAR RECURSOS METRICBEAT ($RESOURCE_TYPE) - Force: $FORCE_MODE"
        echo "======================================================"
        check_prerequisites
        if create_resources "$RESOURCE_TYPE" "$FORCE_MODE"; then
            echo "======================================================"
            print_success "🎉 Creación completada exitosamente"
            case "$RESOURCE_TYPE" in
                "roles")
                    print_info "Rol 'metricbeat_writer' configurado para:"
                    print_info "  • Índices: metricbeat-*, .monitoring-beats-*"
                    print_info "  • Permisos: write, create_index, view_index_metadata"
                    ;;
                "users")
                    print_info "Usuarios creados:"
                    print_info "  • metricbeat_internal → Usuario interno para Metricbeat"
                    print_info "  • monitoring_admin → Acceso web Stack Monitoring"
                    ;;
                "all")
                    print_info "Usuarios y roles configurados para Metricbeat"
                    print_info "🔑 Credenciales configuradas con ELASTIC_PASSWORD"
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
        print_info "MODO: VERIFICAR RECURSOS METRICBEAT ($RESOURCE_TYPE)"
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
        print_info "MODO: ELIMINAR RECURSOS METRICBEAT ($RESOURCE_TYPE) - Force: $FORCE_MODE"
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
        print_info "MODO: LISTAR USUARIOS Y ROLES"
        echo "======================================================"
        check_prerequisites
        if list_resources; then
            echo "======================================================"
            print_success "🎉 Listado completado"
            echo "======================================================"
            exit 0
        else
            echo "======================================================"
            print_error "💥 Error al listar recursos"
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
