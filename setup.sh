#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# ZÁKLADNÉ NASTAVENIA
# ============================================================

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_USER="$(id -un)"
APP_GROUP="$(id -gn)"

APP_SERVICE_NAME="submissionapp"
APP_SERVICE_FILE="/etc/systemd/system/${APP_SERVICE_NAME}.service"

FILEBROWSER_SERVICE_NAME="filebrowser"
FILEBROWSER_SERVICE_FILE="/etc/systemd/system/${FILEBROWSER_SERVICE_NAME}.service"
FILEBROWSER_DATABASE_DIR="/var/lib/filebrowser"
FILEBROWSER_DATABASE="$FILEBROWSER_DATABASE_DIR/filebrowser.db"
FILEBROWSER_PORT="8080"
FILEBROWSER_ADDRESS="127.0.0.1"

FILEBROWSER_ADMIN_USER="admin"
FILEBROWSER_ADMIN_PASSWORD="icom-ic-7300"

CSS_SOURCE="$PROJECT_DIR/custom.css.filebrowserbackup"
CSS_TARGET="$PROJECT_DIR/custom.css"

DATA_DIR="/var/application_data/submission_app"
CLOUD_DIR="$DATA_DIR/cloud/teacher"
EXERCISE_DIR="$DATA_DIR/exercise"
EXERCISE_RESOURCES_DIR="$EXERCISE_DIR/resources"
HOMEWORK_DIR="$DATA_DIR/homework"

TODAY="$(date '+%-d.%-m.%Y')"
TODAY_EXERCISE_DIR="$EXERCISE_DIR/$TODAY"

cd "$PROJECT_DIR"

echo "Projekt: $PROJECT_DIR"
echo "Používateľ služieb: $APP_USER"
echo

# ============================================================
# KONTROLA PROJEKTU
# ============================================================

if [[ ! -f "$PROJECT_DIR/app.py" ]]; then
    echo "Chyba: Súbor app.py sa nenašiel."
    exit 1
fi

if [[ ! -f "$PROJECT_DIR/requirements.txt" ]]; then
    echo "Chyba: Súbor requirements.txt sa nenašiel."
    exit 1
fi

# ============================================================
# INŠTALÁCIA SYSTÉMOVÝCH BALÍKOV A REDISU
# ============================================================

echo "Inštalujem systémové balíky a Redis..."

sudo apt update
sudo apt install -y \
    python3 \
    python3-venv \
    python3-pip \
    redis-server \
    curl \
    ca-certificates

sudo systemctl enable --now redis-server

if ! systemctl is-active --quiet redis-server; then
    echo "Chyba: Redis sa nepodarilo spustiť."
    sudo systemctl --no-pager --full status redis-server || true
    exit 1
fi

echo "Redis je spustený."

# ============================================================
# DÁTOVÉ PRIEČINKY APLIKÁCIE
# ============================================================

echo "Vytváram dátové priečinky..."

sudo mkdir -p \
    "$CLOUD_DIR" \
    "$EXERCISE_RESOURCES_DIR" \
    "$TODAY_EXERCISE_DIR" \
    "$HOMEWORK_DIR"

sudo chown -R "$APP_USER:$APP_GROUP" "$DATA_DIR"
sudo find "$DATA_DIR" -type d -exec chmod 755 {} \;
sudo find "$DATA_DIR" -type f -exec chmod 644 {} \;

echo "Vytvorené priečinky:"
echo "  Cloud:        $CLOUD_DIR"
echo "  Materiály:    $EXERCISE_RESOURCES_DIR"
echo "  Dnešný test:  $TODAY_EXERCISE_DIR"
echo "  Domáce úlohy: $HOMEWORK_DIR"

# ============================================================
# CUSTOM CSS
# ============================================================

if [[ -f "$CSS_SOURCE" ]]; then
    cp -f "$CSS_SOURCE" "$CSS_TARGET"
    chmod 644 "$CSS_TARGET"
    echo "Vytvorený súbor: $CSS_TARGET"
else
    echo "Upozornenie: $CSS_SOURCE neexistuje."
    echo "Custom CSS nebude vytvorený."
fi

# ============================================================
# PYTHON VIRTUÁLNE PROSTREDIE
# ============================================================

if [[ ! -x "$PROJECT_DIR/venv/bin/python" ]]; then
    echo "Vytváram virtuálne prostredie..."
    python3 -m venv "$PROJECT_DIR/venv"
else
    echo "Virtuálne prostredie už existuje."
fi

echo "Inštalujem Python závislosti..."

"$PROJECT_DIR/venv/bin/python" -m pip install --upgrade pip
"$PROJECT_DIR/venv/bin/python" -m pip install \
    -r "$PROJECT_DIR/requirements.txt"

echo "Kontrolujem syntax app.py..."

"$PROJECT_DIR/venv/bin/python" -m py_compile "$PROJECT_DIR/app.py"

# ============================================================
# SYSTEMD SLUŽBA PRE FLASK
# ============================================================

echo "Vytváram službu Submission App..."

sudo tee "$APP_SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Submission App
After=network-online.target redis-server.service
Wants=network-online.target redis-server.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/app.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

# ============================================================
# INŠTALÁCIA FILE BROWSERA
# ============================================================

if ! command -v filebrowser >/dev/null 2>&1; then
    echo "Inštalujem File Browser..."

    curl -fsSL \
        https://raw.githubusercontent.com/filebrowser/get/master/get.sh \
        | sudo bash
else
    echo "File Browser už je nainštalovaný."
fi

FILEBROWSER_BIN="$(command -v filebrowser)"

if [[ ! -x "$FILEBROWSER_BIN" ]]; then
    echo "Chyba: File Browser sa nepodarilo nainštalovať."
    exit 1
fi

echo "File Browser: $FILEBROWSER_BIN"
"$FILEBROWSER_BIN" version

# ============================================================
# DATABÁZA FILE BROWSERA
# ============================================================

sudo mkdir -p "$FILEBROWSER_DATABASE_DIR"
sudo chown -R "$APP_USER:$APP_GROUP" "$FILEBROWSER_DATABASE_DIR"
sudo chmod 750 "$FILEBROWSER_DATABASE_DIR"

# ============================================================
# SYSTEMD SLUŽBA PRE FILE BROWSER
# ============================================================

echo "Vytváram službu File Browser..."

sudo systemctl stop "$FILEBROWSER_SERVICE_NAME" 2>/dev/null || true

sudo tee "$FILEBROWSER_SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=File Browser
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$PROJECT_DIR
ExecStart=$FILEBROWSER_BIN --address=$FILEBROWSER_ADDRESS --port=$FILEBROWSER_PORT --root=$DATA_DIR --database=$FILEBROWSER_DATABASE
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$FILEBROWSER_SERVICE_NAME"

# Prvé spustenie vytvorí databázu a predvoleného administrátora
sudo systemctl start "$FILEBROWSER_SERVICE_NAME"

echo "Čakám na vytvorenie databázy File Browsera..."

for ((i = 1; i <= 20; i++)); do
    if [[ -f "$FILEBROWSER_DATABASE" ]]; then
        break
    fi

    sleep 1
done

if [[ ! -f "$FILEBROWSER_DATABASE" ]]; then
    echo "Chyba: Databáza File Browsera nebola vytvorená."
    sudo journalctl \
        -u "$FILEBROWSER_SERVICE_NAME" \
        -n 100 \
        --no-pager || true
    exit 1
fi

sudo systemctl stop "$FILEBROWSER_SERVICE_NAME"

sudo chown "$APP_USER:$APP_GROUP" "$FILEBROWSER_DATABASE"
sudo chmod 600 "$FILEBROWSER_DATABASE"

# ============================================================
# NASTAVENIE FILE BROWSERA
# ============================================================

echo "Nastavujem File Browser..."

sudo -u "$APP_USER" "$FILEBROWSER_BIN" config set \
    --database "$FILEBROWSER_DATABASE" \
    --address "$FILEBROWSER_ADDRESS" \
    --port "$FILEBROWSER_PORT" \
    --root "$DATA_DIR" \
    --branding.files "$PROJECT_DIR"

# ============================================================
# ADMINISTRÁTOR FILE BROWSERA
# ============================================================

if sudo -u "$APP_USER" "$FILEBROWSER_BIN" users find \
    "$FILEBROWSER_ADMIN_USER" \
    --database "$FILEBROWSER_DATABASE" \
    >/dev/null 2>&1
then
    echo "Aktualizujem používateľa admin..."

    sudo -u "$APP_USER" "$FILEBROWSER_BIN" users update \
        "$FILEBROWSER_ADMIN_USER" \
        --password "$FILEBROWSER_ADMIN_PASSWORD" \
        --perm.admin \
        --perm.create \
        --perm.delete \
        --perm.download \
        --perm.modify \
        --perm.rename \
        --perm.share \
        --database "$FILEBROWSER_DATABASE"
else
    echo "Vytváram používateľa admin..."

    sudo -u "$APP_USER" "$FILEBROWSER_BIN" users add \
        "$FILEBROWSER_ADMIN_USER" \
        "$FILEBROWSER_ADMIN_PASSWORD" \
        --perm.admin \
        --perm.create \
        --perm.delete \
        --perm.download \
        --perm.modify \
        --perm.rename \
        --perm.share \
        --database "$FILEBROWSER_DATABASE"
fi

# ============================================================
# SPUSTENIE SLUŽIEB
# ============================================================

sudo systemctl daemon-reload

sudo systemctl enable "$APP_SERVICE_NAME"
sudo systemctl enable "$FILEBROWSER_SERVICE_NAME"
sudo systemctl enable redis-server

sudo systemctl restart redis-server
sudo systemctl restart "$APP_SERVICE_NAME"
sudo systemctl restart "$FILEBROWSER_SERVICE_NAME"

echo
echo "============================================================"
echo "INŠTALÁCIA BOLA DOKONČENÁ"
echo "============================================================"
echo
echo "Redis:"
echo "  localhost:6379"
echo
echo "File Browser:"
echo "  Adresa: http://127.0.0.1:$FILEBROWSER_PORT"
echo "  Používateľ: $FILEBROWSER_ADMIN_USER"
echo "  Heslo: $FILEBROWSER_ADMIN_PASSWORD"
echo "  Databáza: $FILEBROWSER_DATABASE"
echo "  Súbory: $DATA_DIR"
echo
echo "Stav Submission App:"
sudo systemctl --no-pager --full status "$APP_SERVICE_NAME" || true

echo
echo "Stav File Browsera:"
sudo systemctl --no-pager --full status "$FILEBROWSER_SERVICE_NAME" || true

echo
echo "Stav Redisu:"
sudo systemctl --no-pager --full status redis-server || true
