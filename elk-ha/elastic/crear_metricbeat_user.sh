#!/bin/bash

# Configuración
ELASTIC_HOST="https://localhost:9200"
CA_CERT="/elk-share/certs/ca/ca.crt"
ELASTIC_SUPERUSER="elastic"
ELASTIC_PASSWORD="Alandalus2425"

# Usuarios y contraseñas
METRICBEAT_USER="metricbeat_internal"
METRICBEAT_PASSWORD="Alandalus2425"
MONITORING_USER="monitoring_admin"  # Usuario para acceso web al Stack Monitoring
MONITORING_PASSWORD="Alandalus2425"


# 1. Crear rol personalizado para Metricbeat
echo "➡️  Creando rol 'metricbeat_writer'..."
curl -X PUT -u $ELASTIC_SUPERUSER:$ELASTIC_PASSWORD \
  --cacert "$CA_CERT" \
  "$ELASTIC_HOST/_security/role/metricbeat_writer" \
  -H "Content-Type: application/json" -d '{
  "cluster": ["monitor", "read_ilm", "read_slm"],
  "indices": [
    {
      "names": ["metricbeat-*", ".monitoring-beats-*"],
      "privileges": ["write", "create_index", "view_index_metadata", "create_doc"]
    }
  ]
}'


# 2. Crear usuario interno para Metricbeat
echo "➡️  Creando usuario '$METRICBEAT_USER'..."
curl -X POST -u $ELASTIC_SUPERUSER:$ELASTIC_PASSWORD \
  --cacert "$CA_CERT" \
  "$ELASTIC_HOST/_security/user/$METRICBEAT_USER" \
  -H "Content-Type: application/json" -d "{
  \"password\": \"$METRICBEAT_PASSWORD\",
  \"roles\": [\"metricbeat_writer\", \"beats_system\"],
  \"full_name\": \"Internal Metricbeat User\",
  \"email\": \"metricbeat@example.com\"
}"


# 3. Crear usuario para acceso web al Stack Monitoring
echo "➡️  Creando usuario '$MONITORING_USER' para acceso web..."
curl -X POST -u $ELASTIC_SUPERUSER:$ELASTIC_PASSWORD \
  --cacert "$CA_CERT" \
  "$ELASTIC_HOST/_security/user/$MONITORING_USER" \
  -H "Content-Type: application/json" -d "{
  \"password\": \"$MONITORING_PASSWORD\",
  \"roles\": [\"monitoring_user\", \"kibana_admin\", \"superuser\"],
  \"full_name\": \"Monitoring Administrator\",
  \"email\": \"monitoring@example.com\"
}"

