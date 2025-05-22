#!/usr/bin/env python3

import os
import requests
import time
from datetime import datetime

urls = os.getenv("URLS", "").split(",")
output_dir = "/data/out"
# output_dir = "/elk-share/testuri/out"

os.makedirs(output_dir, exist_ok=True)

while True:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = os.path.join(output_dir, f"testuri_{timestamp}.out")
    
    with open(output_file, "w") as f:
        for url in urls:
            try:
                r = requests.get(url, timeout=5)
                f.write(f"{url} -> {r.status_code}\n")
            except Exception as e:
                f.write(f"{url} -> ERROR: {e}\n")
    
    time.sleep(60)
