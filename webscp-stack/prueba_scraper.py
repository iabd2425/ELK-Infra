#!/usr/bin/env python3

import requests
from bs4 import BeautifulSoup
import time
from datetime import datetime
import os

def extraer_libros():
    url = "http://books.toscrape.com/"
    headers = {
        "User-Agent": "Mozilla/5.0"
    }

    try:
        respuesta = requests.get(url, headers=headers)
        respuesta.raise_for_status()
        respuesta.encoding = 'utf-8'
    except requests.RequestException as e:
        return f"Error al conectar con la web: {e}\n"

    soup = BeautifulSoup(respuesta.text, "html.parser")
    libros = soup.find_all("article", class_="product_pod")

    salida = []
    salida.append("Listado de libros en la página principal:\n")

    for libro in libros:
        titulo = libro.h3.a["title"]
        precio = libro.find("p", class_="price_color").text
        disponibilidad = libro.find("p", class_="instock availability").text.strip()

        salida.append(f"📘 Título: {titulo}")
        salida.append(f"💲 Precio: {precio}")
        salida.append(f"📦 Disponibilidad: {disponibilidad}")
        salida.append("-" * 40)

    return "\n".join(salida)

def main():
    while True:
        timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        log_filename = f"/data/out/prueba_scraper.log.{timestamp}"
        resultado = extraer_libros()

        with open(log_filename, "w", encoding="utf-8") as log_file:
            log_file.write(f"⏱️ Ejecución: {timestamp}\n")
            log_file.write(resultado)

        print(f"[{timestamp}] Datos guardados en {log_filename}")
        
        # Espera 1 hora
        # time.sleep(3600)
        time.sleep(60)

if __name__ == "__main__":
    main()
