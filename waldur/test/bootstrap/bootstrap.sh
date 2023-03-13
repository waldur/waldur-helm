#!/bin/bash
set -e

ls -ltr

echo "[+] Printing environment"
export

echo "[+] Loading content"
python3 load_content.py || true

echo "[+] Finished"

exit 0
