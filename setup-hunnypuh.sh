#!/bin/bash

# Hunnypuh Archiv - Vollautomatisches Setup Skript
# Farben für Ausgaben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logo anzeigen
echo -e "${YELLOW}"
cat << "EOF"
 _   _                       _                   _   _    _    ____ _ _            _ 
| | | |_   _ _ __  _ __  _   _| |_   _ _ __ ___  | | | |  / \  / ___| (_) ___ _ __ | |
| |_| | | | | '_ \| '_ \| | | | | | | | '_ ` _ \ | |_| | / _ \| |   | | |/ _ \ '_ \| |
|  _  | |_| | | | | | | | |_| | | |_| | | | | | ||  _  |/ ___ \ |___| | |  __/ | | |_|
|_| |_|\__,_|_| |_|_| |_|\__,_|_|\__,_|_| |_| |_||_| |_/_/   \_\____|_|_|\___|_| |_(_)
                                                                                        
EOF
echo -e "${NC}"
echo -e "${GREEN}=== Hunnypuh Archiv - Automatisches Setup ===${NC}"
echo -e "${BLUE}Das Skript installiert und konfiguriert alles für dich!${NC}"
echo ""

# Prüfe ob root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Bitte als root ausführen (sudo ./setup-hunnypuh.sh)${NC}"
    exit 1
fi

# Fehlerbehandlung
set -e
trap 'echo -e "${RED}Fehler in Zeile $LINENO${NC}"; exit 1' ERR

# Logging Funktion
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[FEHLER] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNUNG] $1${NC}"
}

# Konfiguration
PROJECT_DIR="/opt/hunnypuh-archiv"
DB_NAME="hunnypuh_archiv"
DB_USER="hunnypuh_user"
DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-20)
SECRET_KEY=$(openssl rand -base64 32)
DOMAIN="localhost"
BACKEND_PORT=8000
FRONTEND_PORT=3000

# Willkommen
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║     🍯 Hunnypuh Archiv - Installationsassistent          ║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Folgende Komponenten werden installiert:"
echo -e "  ${CYAN}•${NC} PostgreSQL 15"
echo -e "  ${CYAN}•${NC} Python 3.11 + FastAPI"
echo -e "  ${CYAN}•${NC} Node.js 20 + React"
echo -e "  ${CYAN}•${NC} Nginx"
echo -e "  ${CYAN}•${NC} Docker & Docker Compose (optional)"
echo ""
echo -e "Installationsverzeichnis: ${YELLOW}$PROJECT_DIR${NC}"
echo -e "Datenbank: ${YELLOW}$DB_NAME${NC}"
echo -e "Backend Port: ${YELLOW}$BACKEND_PORT${NC}"
echo -e "Frontend Port: ${YELLOW}$FRONTEND_PORT${NC}"
echo ""
read -p "Weiter mit Installation? (j/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Jj]$ ]]; then
    exit 1
fi

# 1. System aktualisieren
log "Aktualisiere Systempakete..."
apt-get update && apt-get upgrade -y

# 2. Installiere Abhängigkeiten
log "Installiere benötigte Pakete..."
apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    postgresql \
    postgresql-contrib \
    redis-server \
    nginx \
    python3.11 \
    python3.11-venv \
    python3-pip \
    nodejs \
    npm \
    docker.io \
    docker-compose \
    certbot \
    python3-certbot-nginx \
    ufw \
    fail2ban \
    htop \
    neofetch

# 3. PostgreSQL konfigurieren
log "Konfiguriere PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# Benutzer und Datenbank erstellen
sudo -u postgres psql <<EOF
CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
CREATE DATABASE $DB_NAME OWNER $DB_USER;
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
\c $DB_NAME
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOF

log "PostgreSQL erfolgreich konfiguriert"

# 4. Projektverzeichnis erstellen
log "Erstelle Projektverzeichnis..."
mkdir -p $PROJECT_DIR
mkdir -p $PROJECT_DIR/{backend,frontend,backups,logs,uploads}
mkdir -p $PROJECT_DIR/uploads/{covers,temp}

# 5. Backend Setup
log "Richte Backend ein..."
cd $PROJECT_DIR/backend

# Python Virtual Environment
python3.11 -m venv venv
source venv/bin/activate

# requirements.txt erstellen
cat > requirements.txt <<EOF
fastapi==0.104.1
uvicorn[standard]==0.24.0
sqlalchemy==2.0.23
psycopg2-binary==2.9.9
alembic==1.12.1
pydantic==2.5.0
pydantic-settings==2.1.0
python-multipart==0.0.6
pillow==10.1.0
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-dotenv==1.0.0
httpx==0.25.1
python-magic==0.4.27
boto3==1.34.0
redis==5.0.1
celery==5.3.4
gunicorn==21.2.0
EOF

pip install -r requirements.txt

# Backend main.py erstellen
cat > main.py <<'EOF'
from fastapi import FastAPI, UploadFile, File, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import create_engine, Column, Integer, String, Text, DateTime, Boolean, Float, ForeignKey, Table
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session, relationship
from pydantic import BaseModel
from datetime import datetime
import os
import shutil
from typing import Optional, List
import uuid

# Datenbank
SQLALCHEMY_DATABASE_URL = f"postgresql://{os.getenv('DB_USER', 'hunnypuh_user')}:{os.getenv('DB_PASSWORD', 'password')}@{os.getenv('DB_HOST', 'localhost')}/{os.getenv('DB_NAME', 'hunnypuh_archiv')}"
engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# Models
item_category = Table('item_category', Base.metadata,
    Column('item_id', Integer, ForeignKey('items.id')),
    Column('category_id', Integer, ForeignKey('categories.id'))
)

item_creator = Table('item_creator', Base.metadata,
    Column('item_id', Integer, ForeignKey('items.id')),
    Column('creator_id', Integer, ForeignKey('creators.id'))
)

item_tag = Table('item_tag', Base.metadata,
    Column('item_id', Integer, ForeignKey('items.id')),
    Column('tag_id', Integer, ForeignKey('tags.id'))
)

class Item(Base):
    __tablename__ = "items"
    
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, nullable=False)
    series = Column(String)
    issue_number = Column(String)
    publisher = Column(String)
    release_year = Column(Integer)
    condition = Column(String)
    language = Column(String)
    storage_location = Column(String)
    cover_image_path = Column(String)
    notes = Column(Text)
    is_archived = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    categories = relationship("Category", secondary=item_category, back_populates="items")
    creators = relationship("Creator", secondary=item_creator, back_populates="items")
    tags = relationship("Tag", secondary=item_tag, back_populates="items")

class Category(Base):
    __tablename__ = "categories"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, nullable=False)
    description = Column(Text)
    color_hex = Column(String, default="#F4C542")
    items = relationship("Item", secondary=item_category, back_populates="categories")

class Creator(Base):
    __tablename__ = "creators"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    role = Column(String)
    biography = Column(Text)
    items = relationship("Item", secondary=item_creator, back_populates="creators")

class Tag(Base):
    __tablename__ = "tags"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, nullable=False)
    usage_count = Column(Integer, default=0)
    items = relationship("Item", secondary=item_tag, back_populates="tags")

# Tabellen erstellen
Base.metadata.create_all(bind=engine)

# Pydantic Models
class ItemBase(BaseModel):
    title: str
    series: Optional[str] = None
    issue_number: Optional[str] = None
    publisher: Optional[str] = None
    release_year: Optional[int] = None
    condition: Optional[str] = None
    language: Optional[str] = None
    storage_location: Optional[str] = None
    notes: Optional[str] = None

class ItemCreate(ItemBase):
    pass

class ItemResponse(ItemBase):
    id: int
    cover_image_path: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True

# FastAPI App
app = FastAPI(title="Hunnypuh Archiv API")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Statische Dateien
app.mount("/uploads", StaticFiles(directory="/opt/hunnypuh-archiv/uploads"), name="uploads")

# Dependencies
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# API Routes
@app.get("/")
async def root():
    return {
        "message": "🍯 Hunnypuh Archiv API",
        "version": "1.0.0",
        "status": "running",
        "endpoints": {
            "items": "/api/v1/items",
            "search": "/api/v1/search",
            "docs": "/docs"
        }
    }

@app.get("/api/v1/items", response_model=List[ItemResponse])
async def get_items(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    items = db.query(Item).offset(skip).limit(limit).all()
    return items

@app.post("/api/v1/items", response_model=ItemResponse)
async def create_item(item: ItemCreate, db: Session = Depends(get_db)):
    db_item = Item(**item.dict())
    db.add(db_item)
    db.commit()
    db.refresh(db_item)
    return db_item

@app.get("/api/v1/items/{item_id}", response_model=ItemResponse)
async def get_item(item_id: int, db: Session = Depends(get_db)):
    item = db.query(Item).filter(Item.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item nicht gefunden")
    return item

@app.post("/api/v1/upload/{item_id}")
async def upload_cover(item_id: int, file: UploadFile = File(...), db: Session = Depends(get_db)):
    # Prüfe ob Item existiert
    item = db.query(Item).filter(Item.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item nicht gefunden")
    
    # Speichere Datei
    file_extension = file.filename.split(".")[-1]
    file_name = f"cover_{item_id}_{uuid.uuid4()}.{file_extension}"
    file_path = f"/opt/hunnypuh-archiv/uploads/covers/{file_name}"
    
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    
    # Update Item
    item.cover_image_path = f"/uploads/covers/{file_name}"
    db.commit()
    
    return {"filename": file_name, "path": item.cover_image_path}

@app.get("/api/v1/search")
async def search(q: str, db: Session = Depends(get_db)):
    items = db.query(Item).filter(
        Item.title.ilike(f"%{q}%") | 
        Item.series.ilike(f"%{q}%") |
        Item.notes.ilike(f"%{q}%")
    ).limit(50).all()
    return items

# Health Check
@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow(),
        "database": "connected",
        "storage": os.path.exists("/opt/hunnypuh-archiv/uploads")
    }

EOF

# .env Datei erstellen
cat > .env <<EOF
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_NAME=$DB_NAME
DB_HOST=localhost
SECRET_KEY=$SECRET_KEY
BACKEND_PORT=$BACKEND_PORT
FRONTEND_PORT=$FRONTEND_PORT
UPLOAD_DIR=/opt/hunnypuh-archiv/uploads
EOF

# Systemd Service für Backend
log "Erstelle Systemd Service für Backend..."
cat > /etc/systemd/system/hunnypuh-backend.service <<EOF
[Unit]
Description=Hunnypuh Archiv Backend
After=network.target postgresql.service

[Service]
User=www-data
Group=www-data
WorkingDirectory=$PROJECT_DIR/backend
Environment="PATH=$PROJECT_DIR/backend/venv/bin"
EnvironmentFile=$PROJECT_DIR/backend/.env
ExecStart=$PROJECT_DIR/backend/venv/bin/uvicorn main:app --host 0.0.0.0 --port $BACKEND_PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 6. Frontend Setup
log "Richte Frontend ein..."
cd $PROJECT_DIR/frontend

# React App erstellen
npm create vite@latest . -- --template react-ts

# Abhängigkeiten installieren
npm install
npm install axios react-query react-router-dom @headlessui/react @heroicons/react
npm install -D tailwindcss postcss autoprefixer

# Tailwind konfigurieren
npx tailwindcss init -p

cat > tailwind.config.js <<EOF
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        'comic-yellow': '#F4C542',
        'comic-yellow-light': '#FFE5A3',
        'comic-yellow-dark': '#DAA520',
        'duck-orange': '#F97316',
        'mickey-red': '#DC2626',
        'daisy-pink': '#FDA4AF',
        'sky-blue': '#7DD3FC',
        'grass-green': '#86EFAC',
        'paper-cream': '#FEF9E7',
        'old-paper': '#FDF5E6',
        'ink-black': '#1E1E1E',
      },
      fontFamily: {
        'comic': ['"Comic Neue"', 'cursive'],
        'title': ['"KG Second Chances"', 'cursive'],
      },
      boxShadow: {
        'comic': '8px 8px 0 rgba(0, 0, 0, 0.1)',
        'soft': '4px 4px 0 #E5E7EB',
      },
      animation: {
        'float': 'float 3s ease-in-out infinite',
        'bounce-slow': 'bounce 2s infinite',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-10px)' },
        }
      }
    },
  },
  plugins: [],
}
EOF

# CSS erstellen
cat > src/index.css <<'EOF'
@import url('https://fonts.googleapis.com/css2?family=Comic+Neue:wght@400;700&display=swap');
@tailwind base;
@tailwind components;
@tailwind utilities;

@font-face {
  font-family: 'KG Second Chances';
  src: url('https://fonts.cdnfonts.com/s/15806/KGSecondChancesSketch.woff') format('woff');
}

body {
  background-color: #FEF9E7;
  background-image: radial-gradient(circle at 10px 10px, #FFE5A3 2px, transparent 2px), 
                    radial-gradient(circle at 30px 30px, #F4C542 2px, transparent 2px);
  background-size: 40px 40px, 80px 80px;
  min-height: 100vh;
}

.comic-panel {
  @apply relative bg-paper-cream border-4 border-ink-black rounded-lg p-4;
  box-shadow: 12px 12px 0 rgba(0, 0, 0, 0.1);
}

.comic-panel::after {
  content: '';
  @apply absolute top-2 left-2 right-0 bottom-0 bg-black bg-opacity-5 -z-10 rounded-lg;
}

.speech-bubble {
  @apply relative bg-white border-2 border-ink-black rounded-3xl rounded-bl-none p-3;
  filter: drop-shadow(4px 4px 0 rgba(0, 0, 0, 0.1));
}

.speech-bubble::before {
  content: '';
  @apply absolute -bottom-3 left-4 w-0 h-0;
  border: 12px solid transparent;
  border-top-color: white;
  border-bottom: 0;
  border-left: 0;
  filter: drop-shadow(2px 2px 0 rgba(0, 0, 0, 0.1));
}

.comic-card {
  @apply transition-all duration-300 hover:-translate-y-1 hover:rotate-1;
}
EOF

# App.tsx erstellen
cat > src/App.tsx <<'EOF'
import React from 'react';
import { BrowserRouter as Router, Routes, Route, Link } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from 'react-query';
import { MagnifyingGlassIcon, PlusCircleIcon, HomeIcon } from '@heroicons/react/24/outline';

const queryClient = new QueryClient();

function HomePage() {
  return (
    <div className="min-h-screen bg-paper-cream">
      {/* Comic Header */}
      <header className="comic-panel mb-8 bg-gradient-to-r from-comic-yellow to-duck-orange">
        <div className="container mx-auto px-4 py-8">
          <h1 className="font-title text-6xl text-center text-ink-black mb-4 animate-bounce-slow">
            🍯 Hunnypuh Archiv
          </h1>
          <p className="font-comic text-xl text-center text-ink-black">
            Deine digitale Comic-Sammlung im Entenhausen-Stil
          </p>
        </div>
      </header>

      {/* Search Bar */}
      <div className="container mx-auto px-4 mb-8">
        <div className="speech-bubble max-w-2xl mx-auto">
          <div className="flex items-center bg-white rounded-full border-2 border-ink-black p-2">
            <MagnifyingGlassIcon className="w-6 h-6 text-gray-400 ml-2" />
            <input
              type="text"
              placeholder="Durchstöbere deine Sammlung..."
              className="flex-1 px-4 py-2 font-comic focus:outline-none"
            />
            <button className="bg-comic-yellow text-ink-black px-6 py-2 rounded-full font-comic border-2 border-ink-black hover:bg-comic-yellow-dark transition-colors">
              Suchen
            </button>
          </div>
        </div>
      </div>

      {/* Comic Grid */}
      <div className="container mx-auto px-4">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          {/* Beispiel-Karten */}
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="comic-card comic-panel group cursor-pointer">
              <div className="aspect-w-3 aspect-h-4 mb-4 overflow-hidden rounded-lg">
                <div className="w-full h-48 bg-gradient-to-br from-comic-yellow to-sky-blue flex items-center justify-center">
                  <span className="text-6xl">📚</span>
                </div>
              </div>
              <h3 className="font-title text-xl mb-2">Lustiges Taschenbuch #{i}</h3>
              <p className="font-comic text-sm text-gray-600">Egmont · 2024</p>
              <div className="mt-4 flex gap-2">
                <span className="speech-bubble text-xs py-1 px-3">Near Mint</span>
                <span className="speech-bubble text-xs py-1 px-3">🇩🇪</span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Add Button */}
      <Link
        to="/admin"
        className="fixed bottom-8 right-8 bg-comic-yellow text-ink-black p-4 rounded-full border-4 border-ink-black shadow-comic hover:bg-duck-orange transition-all hover:scale-110"
      >
        <PlusCircleIcon className="w-8 h-8" />
      </Link>
    </div>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <Router>
        <Routes>
          <Route path="/" element={<HomePage />} />
        </Routes>
      </Router>
    </QueryClientProvider>
  );
}

export default App;
EOF

# 7. Nginx konfigurieren
log "Konfiguriere Nginx..."
cat > /etc/nginx/sites-available/hunnypuh <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # SSL (für Entwicklung selbstsigniert)
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    # Frontend
    location / {
        proxy_pass http://localhost:$FRONTEND_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Backend API
    location /api/ {
        proxy_pass http://localhost:$BACKEND_PORT/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # Backend Docs
    location /docs {
        proxy_pass http://localhost:$BACKEND_PORT/docs;
    }

    # Uploads
    location /uploads/ {
        alias $PROJECT_DIR/uploads/;
        expires 30d;
    }
}
EOF

# SSL Zertifikat für Entwicklung erstellen
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/key.pem \
    -out /etc/nginx/ssl/cert.pem \
    -subj "/C=DE/ST=Berlin/L=Berlin/O=Hunnypuh/CN=$DOMAIN"

# Nginx aktivieren
ln -sf /etc/nginx/sites-available/hunnypuh /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# 8. Firewall konfigurieren
log "Konfiguriere Firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow $BACKEND_PORT/tcp
ufw allow $FRONTEND_PORT/tcp
echo "y" | ufw enable

# 9. Services starten
log "Starte Services..."
systemctl daemon-reload
systemctl enable hunnypuh-backend
systemctl start hunnypuh-backend
systemctl enable nginx
systemctl restart nginx

# 10. Fertigstellung
log "Installation abgeschlossen!"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     🎉 Hunnypuh Archiv wurde erfolgreich installiert!   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Zugangsdaten:${NC}"
echo -e "  Frontend:   ${YELLOW}http://localhost:$FRONTEND_PORT${NC}"
echo -e "  Backend:    ${YELLOW}http://localhost:$BACKEND_PORT${NC}"
echo -e "  API Docs:   ${YELLOW}http://localhost:$BACKEND_PORT/docs${NC}"
echo -e "  Datenbank:  ${YELLOW}postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME${NC}"
echo ""
echo -e "${CYAN}Verzeichnisse:${NC}"
echo -e "  Projekt:    ${YELLOW}$PROJECT_DIR${NC}"
echo -e "  Uploads:    ${YELLOW}$PROJECT_DIR/uploads${NC}"
echo -e "  Backups:    ${YELLOW}$PROJECT_DIR/backups${NC}"
echo ""
echo -e "${CYAN}Services:${NC}"
echo -e "  Backend:    ${YELLOW}systemctl status hunnypuh-backend${NC}"
echo -e "  PostgreSQL: ${YELLOW}systemctl status postgresql${NC}"
echo -e "  Nginx:      ${YELLOW}systemctl status nginx${NC}"
echo ""
echo -e "${CYAN}Nächste Schritte:${NC}"
echo -e "  1. Öffne ${YELLOW}http://localhost:$FRONTEND_PORT${NC} im Browser"
echo -e "  2. Teste die API unter ${YELLOW}http://localhost:$BACKEND_PORT/docs${NC}"
echo -e "  3. Füge deine ersten Comics hinzu!"
echo ""
echo -e "${PURPLE}Viel Spaß mit deinem Hunnypuh Archiv! 🍯${NC}"

# Konfiguration in Datei speichern
cat > $PROJECT_DIR/install_config.txt <<EOF
Hunnypuh Archiv Installation
============================
Installationsdatum: $(date)
Datenbank: $DB_NAME
DB User: $DB_USER
DB Password: $DB_PASSWORD
Secret Key: $SECRET_KEY
Installationspfad: $PROJECT_DIR
EOF

chmod 600 $PROJECT_DIR/install_config.txt

log "Konfiguration wurde in $PROJECT_DIR/install_config.txt gespeichert"
