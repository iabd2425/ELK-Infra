FROM python:3.11-slim

# Metadatos
LABEL maintainer="IABD Team"
LABEL description="Web Scraper IABD2425 Swarm"
LABEL version="2.0"

# Instalar dependencias del sistema incluyendo herramientas de red
# Nota: Cargamos beautifulsoup4 en el sistema y no en requirements (problemas DNS)
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    dnsutils \
    iputils-ping \
    net-tools \
    python3-bs4 \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*


# Crear usuario no-root por seguridad
RUN groupadd -r -g 1001 webscp && useradd -m -u 1001 -g 1001 -o -c "Usuario Scraper" -s /bin/bash webscp

# Configurar directorio de trabajo
WORKDIR /app

# Copiar e instalar dependencias Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar código fuente
COPY booking_scraper.py .
# COPY prueba_scraper.py .

# Crear directorio de datos y cambiar permisos
RUN mkdir -p /data/out && chown -R webscp:webscp /data /app

# Cambiar a usuario no-root
USER webscp

# Configurar variables de entorno
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# AÑADIDO: Variables de entorno para requests y urllib3
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# Health check mejorado
# HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    # CMD python -c "import os; exit(0 if os.path.exists('/data/out') else 1)"

# Comando por defecto
CMD ["python", "booking_scraper.py"]
# CMD ["python", "prueba_scraper.py"]
