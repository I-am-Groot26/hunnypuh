#!/bin/bash

# Hunnypuh Archiv - Quick Start Skript
# Einfach ausführen und loslegen!

echo "🍯 Hunnypuh Archiv - Quick Start"
echo "================================"

# Lade das Hauptskript herunter
echo "📥 Lade Installationsskript herunter..."
curl -O https://raw.githubusercontent.com/dein-repo/hunnypuh-archiv/main/setup-hunnypuh.sh

# Mach es ausführbar
chmod +x setup-hunnypuh.sh

# Führe es aus
echo "🚀 Starte Installation..."
sudo ./setup-hunnypuh.sh
