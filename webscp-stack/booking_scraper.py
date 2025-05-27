import requests
from bs4 import BeautifulSoup
import json
import re
import time
import random
from urllib.parse import urlparse, parse_qs
from datetime import date, timedelta, datetime 
import logging
import os
import schedule

OUT_DIRECTORY = '/data/out' #Cambiar a '/data/out' en producción

def configurar_logging():
    # Ruta a fichero logging
    log_filename = f"scraper_{datetime.now().strftime('%Y%m%d')}.log"
    full_log_path = os.path.join(OUT_DIRECTORY, log_filename)

    #Crea el directorio de salida en caso de que no exista
    if not os.path.exists(OUT_DIRECTORY):
        os.makedirs(OUT_DIRECTORY)

    write_permission = False
    try:
        # Intenta abrir el fichero en modo append para comprobar los permisos de escritura
        # y se asegura de que el manejador del fichero se cierre inmediatamente después de la comprobación.
        with open(full_log_path, 'a') as f:
            pass
        write_permission = True
    except IOError as e:
        write_permission = False
        print(f"Warning: No se puede escribir en {full_log_path}. Revise los permisos de escritura. Error: {e}")

    # Configuración básica del logging
    logging.basicConfig(
        filename=full_log_path,  # Nombre del archivo de log (corrección aquí)
        level=logging.INFO,      # Nivel mínimo de mensajes que se guardarán
        format='%(asctime)s - SCRAPER - %(levelname)s - %(message)s'  # Formato del mensaje
    )


def get_province_from_dest_id(dest_id):
    """Mapea ID con nombre de provincia."""
    province_map = {
        '1363': 'Almería',
        '755': 'Granada',
        '766': 'Málaga',
        '747': 'Cadíz',
        '774': 'Sevilla',
        '758': 'Huelva',
        '750': 'Cordoba',
        '759': 'Jaen',
    }
    return province_map.get(dest_id, 'Unknown Province')

def scrape_booking_region(dest_id, checkin_date, checkout_date):
    """
    Extrae datos de hoteles de Booking.com para una región especificada basada en dest_id.

    Parámetros:
        dest_id (str): El ID de destino para la región (ej. '1363' para Almería).
        checkin_date (str): Fecha de entrada en formato 'YYYY-MM-DD'.
        checkout_date (str): Fecha de salida en formato 'YYYY-MM-DD'.

    Retorna:
        list: Una lista de diccionarios, donde cada diccionario representa un hotel.
    """
    # URL base para los resultados de búsqueda de Booking.com
    # Las fechas y la moneda se añadirán como parámetros de consulta.
    # Se añadió selected_currency=EUR para intentar forzar precios en EUR.
    base_url = f"https://www.booking.com/searchresults.es.html?lang=es%E2%82%8AC&dest_id={dest_id}&dest_type=region&ac_langcode=es&nflt=ht_id%3D204&shw_aparth=0&selected_currency=EUR&checkin={{}}&checkout={{}}"
    url = base_url.format(checkin_date, checkout_date)

    # Obtiene el nombre de la provincia a partir del dest_id
    province_name = get_province_from_dest_id(dest_id)

    # Agentes de usuario
    user_agents = [
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15',
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36',
    ]
    headers = {
        'User-Agent': random.choice(user_agents)
    }

    hotel_list = []

    try:
        # Añade un retraso aleatorio antes de hacer la solicitud
        time.sleep(random.uniform(0.3, 0.5)) # Retraso entre 0.3 y 0.5 segundos
        logging.info(f"Obteniendo resultados de dest_id {dest_id} ({province_name}) el {checkin_date}...") # Corrección aquí

        response = requests.get(url, headers=headers)
        response.raise_for_status() # Lanza una excepción para códigos de estado incorrectos
        
        soup = BeautifulSoup(response.content, 'html.parser')

        # Encuentra todos los listados de hoteles en la página
        # Necesitarás inspeccionar el HTML de la página de resultados de búsqueda
        # para encontrar el selector correcto para los listados de hoteles individuales.
        # Este es un selector de marcador de posición.
        hotels = soup.select('div[data-testid="property-card"]')
        logging.info(f"Encontrados {len(hotels)} hoteles en la página de resultados de búsqueda de {province_name}.") # Log Número de hoteles encontrados
        for hotel in hotels:
            hotel_data = {}

            # Extrae puntos de datos
            # Necesitarás inspeccionar el HTML para cada punto de datos y encontrar su selector.
            # Estos son selectores y lógica de marcador de posición.

            # URL hotel (sin fechas)
            try:
                url_element = hotel.select_one('a[data-testid="title-link"]')
                if url_element and 'href' in url_element.attrs:
                    full_url = url_element['href']
                    hotel_data['url'] = full_url # Mantiene la URL completa para extraer la localidad

                    # Extrae el ID de la ruta de la URL (texto después del último '/' y antes de '.html')
                    last_part = full_url.split('/')[-1]
                    hotel_id_with_extension = last_part.split('.html')[0]
                    # Eliminar todo lo que va después del primer punto inclusive
                    hotel_id = hotel_id_with_extension.split('.')[0]
                    hotel_data['id'] = hotel_id

                    # Extrae la localidad de la URL
                    parsed_hotel_url = urlparse(full_url)
                    hotel_query_params = parse_qs(parsed_hotel_url.query)
                    locality = hotel_query_params.get('ss', [None])[0]
                    if locality:
                        # Reemplaza '+' con espacios
                        hotel_data['localidad'] = locality.replace('+', ' ')
                    else:
                        hotel_data['localidad'] = None


                else:
                    hotel_data['url'] = None
                    hotel_data['id'] = None
                    hotel_data['localidad'] = None # También establece la localidad a None si falta la URL
            except Exception as e:
                logging.error(f"Error obteniendo url, id, o localidad: {e}") #Localidad
                hotel_data['url'] = None
                hotel_data['id'] = None
                hotel_data['localidad'] = None # También establece la localidad a None en caso de error

            # Nombre
            try:
                name_element = hotel.select_one('div[data-testid="title"]')
                hotel_data['nombre'] = name_element.get_text(strip=True) if name_element else None
            except Exception as e:
                logging.error(f"Error obteniendo nombre del hotel: {e}")
                hotel_data['nombre'] = None

            # marca (A menudo no está directamente disponible en los resultados de búsqueda, podría ser necesario visitar la página del hotel)
            hotel_data['marca'] = None # Marcador de posición

            # Dirección y Localidad
            try:
                address_element = hotel.select_one('span[data-testid="address"]')
                if address_element:
                    full_address = address_element.get_text(strip=True)
                    # Asumiendo que la localidad es la primera parte antes de una coma o la cadena completa
                    address_parts = full_address.split(',', 1)
                    hotel_data['localidad'] = address_parts[0].strip()
                    hotel_data['Dirección'] = full_address # Mantiene la dirección completa como Dirección
                else:
                    hotel_data['localidad'] = None
                    hotel_data['Dirección'] = None
            except Exception as e:
                logging.error(f"Error obteniendo dirección o localidad: {e}")
                hotel_data['localidad'] = None
                hotel_data['Dirección'] = None


            # Coordenadas (A menudo no están directamente disponibles en los resultados de búsqueda, podría ser necesario visitar la página del hotel o usar geocodificación)
            hotel_data['Coordenadas'] = None # Marcador de posición

            # Servicios populares (A menudo no están directamente disponibles en los resultados de búsqueda, podría ser necesario visitar la página del hotel)
            hotel_data['Servicios populares'] = None # Marcador de posición

            # Descripción (A menudo no está completamente disponible en los resultados de búsqueda, podría ser necesario visitar la página del hotel)
            hotel_data['Descripción'] = None # Marcador de posición

            # Puntuación, Opinión, Numero comentarios
            try:
                review_score_container = hotel.select_one('div[data-testid="review-score"]')
                if review_score_container:
                    # Obtiene todos los textos de los divs hijos directos
                    score_texts = [div.get_text(strip=True) for div in review_score_container.select(':scope > div')]

                    # Asigna según el índice, similar al fragmento proporcionado
                    # Puntuación (valor numérico del índice 0)
                    if len(score_texts) > 0 and score_texts[0]:
                        try:
                            hotel_data['Puntuación'] = float(score_texts[0])
                        except (ValueError, TypeError):
                            hotel_data['Puntuación'] = None
                    else:
                        hotel_data['Puntuación'] = None

                    # Opinión (del índice 1)
                    if len(score_texts) > 1 and score_texts[1]:
                        try:
                            # Reemplaza la coma por un punto para la conversión a flotante
                            opinion_str = score_texts[1].replace(',', '.')
                            hotel_data['Opinión'] = float(opinion_str)
                        except (ValueError, TypeError):
                            hotel_data['Opinión'] = None
                    else:
                        hotel_data['Opinión'] = None

                    # Numero comentarios (valor numérico del índice 2 usando split)
                    if len(score_texts) > 2 and score_texts[2]:
                        num_comments_text = score_texts[2]
                        # Usa regex para encontrar el número de comentarios
                        match = re.search(r'\d+', num_comments_text)
                        # Extrae solo el número y convierte a entero
                        try:
                            hotel_data['Numero comentarios'] = int(match.group(0)) if match else None
                        except (ValueError, TypeError):
                            hotel_data['Numero comentarios'] = None
                    else:
                        hotel_data['Numero comentarios'] = None

                else:
                    hotel_data['Puntuación'] = None
                    hotel_data['Opinión'] = None
                    hotel_data['Numero comentarios'] = None

            except Exception as e:
                logging.error(f"Error obteniendo puntuación, opinión o número de comentarios: {e}")
                hotel_data['Puntuación'] = None
                hotel_data['Opinión'] = None
                hotel_data['Numero comentarios'] = None


            # Fecha entrada (Proporcionada por el usuario)
            hotel_data['Fecha entrada'] = checkin_date

            # Fecha salida (Proporcionada por el usuario)
            hotel_data['Fecha salida'] = checkout_date

            # Precio
            price_text = None
            try:
                price_element = hotel.select_one('span[data-testid="price-and-discounted-price"]')
                if price_element:
                     price_text = price_element.get_text(strip=True)
                else:
                    # A veces el precio está en una estructura diferente
                    price_element_alt = hotel.select_one('div[data-testid="price-and-discounted-price"] span')
                    if price_element_alt:
                        price_text = price_element_alt.get_text(strip=True)

                hotel_data['Precio_texto'] = price_text # Almacena el texto original para depuración

                if price_text:
                    # Limpia la cadena de precio: elimina '€', espacios y reemplaza la coma por un punto
                    cleaned_price_text = price_text.replace('€', '').replace(' ', '').replace('.', '').replace(',', '.') # Se añadió .replace('.', '') para eliminar separadores de miles
                    try:
                        # Convierte a entero
                        hotel_data['Precio'] = int(cleaned_price_text)
                    except (ValueError, TypeError):
                        logging.error(f"Error al convertir el precio a entero: {cleaned_price_text}")
                        hotel_data['Precio'] = None
                else:
                    hotel_data['Precio'] = None

            except Exception as e:
                logging.error(f"Error obteniendo o procesando el precio: {e}")
                hotel_data['Precio'] = None


            # Extrae detalles adicionales de la página individual del hotel
            if hotel_data.get('url'):
                hotel_details = scrape_hotel_details(hotel_data['url'])
                if hotel_details:
                    # Construye el diccionario en el orden deseado
                    ordered_hotel_data = {
                        'url': hotel_data.get('url'),
                        'id': hotel_data.get('id'),
                        'nombre': hotel_data.get('nombre'),
                        'marca': hotel_details.get('marca'), # Obtiene marca de hotel_details
                        'destacados': hotel_details.get('Destacados'), # Añade Destacados
                        'provincia': province_name, # Añade el nombre de la provincia aquí
                        'localidad': hotel_data.get('localidad'), # Añade la localidad aquí
                        'direccion': hotel_details.get('Dirección_detalle'), # Obtiene Dirección de hotel_details
                        'location': { # Crea un diccionario anidado para las coordenadas
                            'lat': hotel_details.get('lat'), # Obtiene lat de hotel_details
                            'lon': hotel_details.get('lon'), # Obtiene lon de hotel_details
                        },
                        'servicios': hotel_details.get('Servicios populares'), # Obtiene Servicios populares de hotel_details
                        'descripcion': hotel_details.get('Descripción'), # Obtiene Descripción de hotel_details
                        'puntuacion': hotel_data.get('Puntuación'),
                        'opinion': hotel_data.get('Opinión'),
                        'comentarios': hotel_data.get('Numero comentarios'),
                        'fechaEntrada': hotel_data.get('Fecha entrada'),
                        'fechaSalida': hotel_data.get('Fecha salida'),
                        'precio': hotel_data.get('Precio'), # Usa el precio procesado
                    }
                    # Elimina claves con valores None o listas vacías para mantener la salida limpia
                    hotel_data = {k: v for k, v in ordered_hotel_data.items() if v is not None and v != []}


            hotel_list.append(hotel_data)

        # TODO: Implementar paginación si es necesario


    except requests.exceptions.RequestException as e:
        logging.error(f"Error al obtener la página de resultados: {e}")
        return None

    return hotel_list

def scrape_hotel_details(url):
    """
    Extrae detalles adicionales de la página individual de un hotel en Booking.com.

    Parámetros:
        url (str): La URL de la página individual del hotel.

    Retorna:
        dict: Un diccionario que contiene detalles adicionales del hotel.
    """
    user_agents = [
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15',
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36',
    ]
    headers = {
        'User-Agent': random.choice(user_agents)
    }

    details = {}

    try:
        # Añade un retraso aleatorio antes de hacer la solicitud
        time.sleep(random.uniform(0.3, 0.5)) # Retraso entre 0.3 y 0.5 segundos

        # logging.info(f"Obteniendo detalles del hotel: {url}") # Corrección aquí
        response = requests.get(url, headers=headers)
        response.raise_for_status() # Lanza una excepción para códigos de estado incorrectos

        soup = BeautifulSoup(response.content, 'html.parser')

        # Extrae puntos de datos adicionales de la página del hotel
        # Necesitarás inspeccionar el HTML de la página individual de un hotel
        # para encontrar los selectores correctos para cada punto de datos.
        # Estos son selectores y lógica de marcador de posición.

        # Destacados
        try:
            # Usa el selector corregido para el contenedor principal de Destacados
            highlight_container = soup.select_one('span.hp__hotel_ratings.pp-header__badges.pp-header__badges--combined div[data-capla-component-boundary="b-property-web-property-page/Badges"]')
            if highlight_container:
                # Selecciona todos los elementos span o div dentro del contenedor
                highlight_elements = highlight_container.select('span, div')
                # Extrae el texto de cada elemento y almacénalo en una lista, filtrando cadenas vacías
                extracted_highlights = [elem.get_text(strip=True) for elem in highlight_elements if elem.get_text(strip=True)]

                # Filtra elementos que parecen estar concatenados (heurística: busca minúscula seguida de mayúscula sin espacio)
                # Elimina duplicados
                filtered_highlights = []
                seen_highlights = set()
                for highlight in extracted_highlights:
                    # Verifica el patrón como "aB" (minúscula seguida de mayúscula)
                    if re.search(r'[a-z][A-Z]', highlight):
                        continue # Omite si se encuentra el patrón

                    # Añade a la lista filtrada y al conjunto visto si no es un duplicado
                    if highlight not in seen_highlights:
                        filtered_highlights.append(highlight)
                        seen_highlights.add(highlight)

                details['Destacados'] = filtered_highlights
            else:
                details['Destacados'] = [] # Usa una lista vacía si no se encuentra el contenedor

        except Exception as e:
            logging.error(f"Error obteniendo destacados del hotel: {e}")
            details['Destacados'] = [] # Usa una lista vacía en caso de error

        # marca
        try:
            brand_element = soup.select_one('div.d7b319a0ec div.b08850ce41')
            details['marca'] = brand_element.get_text(strip=True) if brand_element else None
        except Exception as e:
            logging.error(f"Error obteniendo marca del hotel: {e}")
            details['marca'] = None

        # Coordenadas
        try:
            coords_element = soup.select_one('a#map_trigger_header_pin')
            coords_data = None
            if coords_element and 'data-atlas-latlng' in coords_element.attrs:
                coords_str = coords_element['data-atlas-latlng']
                if coords_str:
                    lat, lon = coords_str.split(',')
                    details['lat'] = float(lat)
                    details['lon'] = float(lon)
            else:
                # Alternativa a las meta tags si no se encuentra el selector principal
                lat_meta = soup.find('meta', {'property': 'booking_com:location:latitude'})
                lon_meta = soup.find('meta', {'property': 'booking_com:location:longitude'})
                coords_content = None
                if lat_meta and 'content' in lat_meta.attrs and lon_meta and 'content' in lon_meta.attrs:
                    coords_content = f"{lat_meta['content']},{lon_meta['content']}"

                if not coords_content or coords_content == ',':
                     # Intenta meta tag alternativa
                     geo_position_meta = soup.find('meta', {'name': 'geo.position'})
                     if geo_position_meta and 'content' in geo_position_meta.attrs:
                          coords_content = geo_position_meta['content']

                if coords_content and coords_content != ',':
                    lat, lon = coords_content.split(',')
                    details['lat'] = float(lat)
                    details['lon'] = float(lon)

        except Exception as e:
            logging.error(f"Error obteniendo coordenadas del hotel: {e}")
            details['lat'] = None
            details['lon'] = None

        # Servicios populares
        try:
            amenities_list = soup.select('div.hp--popular_facilities ul.e9f7361569 li.b0bf4dc58f div.aa8988bf9c span.f006e3fcbd')
            details['Servicios populares'] = [amenity.get_text(strip=True) for amenity in amenities_list] if amenities_list else [] # Usa una lista vacía si no se encuentra ninguno
        except Exception as e:
            logging.error(f"Error obteniendo servicios populares del hotel: {e}")
            details['Servicios populares'] = [] # Usa una lista vacía en caso de error

        # Descripción
        try:
            description_element = soup.select_one('p[data-testid="property-description"]')
            details['Descripción'] = description_element.get_text(strip=True) if description_element else None
        except Exception as e:
            logging.error(f"Error obteniendo descripción del hotel: {e}")
            details['Descripción'] = None

        # Dirección (from hotel page)
        try:
            address_container = soup.select_one('div.b99b6ef58f.cb4b7a25d9')
            if address_container:
                full_text = address_container.get_text(strip=True)
                # Encuentra el segundo div dentro del contenedor
                second_div = address_container.select_one('div:nth-of-type(2)')
                if second_div:
                    second_div_text = second_div.get_text(strip=True)
                    # Divide el texto completo por el texto del segundo div
                    address_parts = full_text.split(second_div_text, 1)
                    if address_parts:
                        extracted_address = address_parts[0].strip()
                    else:
                        extracted_address = full_text.strip() # Alternativa si la división falla
                else:
                    extracted_address = full_text.strip() # Si no hay segundo div, toma todo el texto

                # Encuentra "España" y trunca
                if extracted_address:
                    espana_index = extracted_address.find('España')
                    if espana_index != -1:
                        # Incluye "España" en el resultado
                        details['Dirección_detalle'] = extracted_address[:espana_index + len('España')]
                    else:
                        details['Dirección_detalle'] = extracted_address # Mantiene el original si no se encuentra "España"
                else:
                    details['Dirección_detalle'] = None # Mantiene None si no se extrajo dirección
            else:
                details['Dirección_detalle'] = None
        except Exception as e:
            logging.error(f"Error obteniendo dirección del hotel: {e}")
            details['Dirección_detalle'] = None

        # Precio (Ya extraído de los resultados de búsqueda, pero se confirma el selector si es necesario)
        # El precio en la página individual podría ser diferente o más detallado.
        # Por ahora, nos basaremos en el precio de los resultados de búsqueda como se solicitó inicialmente.
        # Si se necesita un precio más específico de la página del hotel, esta sección se actualizaría.
        # try:
        #     price_element = soup.select_one('selector_for_price_on_hotel_page')
        #     details['Precio'] = price_element.get_text(strip=True) if price_element else None
        # except Exception as e:
        #     details['Precio'] = None


    except requests.exceptions.RequestException as e:
        logging.error(f"Error al obtener la página del hotel {url}: {e}")
        return None

    return details

def scraping():
    configurar_logging()

    logging.info("Inicio de scraper booking.")

    # Obtiene la fecha de hoy como fecha de entrada inicial
    start_date = date.today()

    # Lista de IDs de destino para las provincias a extraer
    # '1363': 'Almería'
    # '755': 'Granada'
    dest_ids_to_scrape = ['1363', '755', '766', '747', '774', '758', '750', '759']
    # dest_ids_to_scrape = ['1363'] #['1363'] # Descomenta esta línea y comenta la anterior para extraer solo Almería

    # Extrae para cada provincia y para X días consecutivos
    for dest_id in dest_ids_to_scrape:
        province_name = get_province_from_dest_id(dest_id)
        # Bucle para N días consecutivos (i va de 0 a 2)
        for i in range(30): # Cambiado a range(N) para N días
            checkin_date = start_date + timedelta(days=i)
            checkout_date = checkin_date + timedelta(days=1) # Estancia de 1 día

            checkin_str = checkin_date.strftime("%Y-%m-%d")
            checkout_str = checkout_date.strftime("%Y-%m-%d")

            logging.info(f"Iniciando scraping para {province_name} para el {checkin_str}")
            hotels_data = scrape_booking_region(dest_id, checkin_str, checkout_str)

            if hotels_data:
                # Define el nombre del archivo basado en la provincia y la fecha de entrada
                json_filename = f"{province_name.lower().replace(' ', '_')}_{checkin_date.strftime('%Y%m%d')}.ndjson" # Usando .jsonl para JSON delimitado por líneas
                full_json_path = os.path.join(OUT_DIRECTORY, json_filename)
                with open(full_json_path, 'w', encoding='utf-8') as f:
                    for hotel in hotels_data:
                        # print(f"Escribiendo datos del hotel en JSON: {hotel}") # Impresión de depuración para los datos del hotel antes de escribir
                        try:
                            linea_json = json.dumps(hotel, ensure_ascii=False)
                            f.write(linea_json + "\n")
                        except Exception as e:
                            print(f"Error escribiendo datos del hotel en JSON: {e} para el hotel: {hotel.get('nombre', 'N/A')}")
                logging.info(f"Fin de scraping para {province_name} para el {checkin_str}. Guardado en {full_json_path}")
            else:
                logging.error(f"Error al obtener datos para {province_name} para el {checkin_str}")
    logging.info("Fin de scraper booking.")

if __name__ == "__main__":
    scraping()
    # Descomentar el siguiente bloque en producción
    schedule.every().day.at("00:30").do(scraping)
    while True:
        schedule.run_pending()
        time.sleep(60)  # Espera 60 segundos entre comprobaciones