#!/bin/bash
# Firecrawl + SearXNG native service installation for workstation VM.
# Downloaded and executed by cloud-init. Reads env vars from /etc/profile.d/llm-endpoints.sh.
#
# Services installed:
#   SearXNG          — metasearch engine       (port 8888)
#   Firecrawl API    — web scraper API         (port 3002)
#   Playwright       — browser microservice    (port 3000)
#   Prefetch Worker  — job queue prefetcher    (port 3006)
#   Scrape Worker    — scrape job processor    (port 3005)
#   Extract Worker   — LLM-powered extractor
#
# Infrastructure: Redis (6379), PostgreSQL (5432), RabbitMQ (5672)
set -euo pipefail
exec > >(tee -a /var/log/workstation-firecrawl-setup.log) 2>&1
echo "=== Firecrawl Setup Started: $(date) ==="

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Validate required env vars
: "${LLM_ADMIN_USER:?LLM_ADMIN_USER not set}"
: "${MEDIUM_LLM_BASE_URL:?MEDIUM_LLM_BASE_URL not set}"
: "${MEDIUM_LLM_MODEL:?MEDIUM_LLM_MODEL not set}"

# ============================================================
# 1. APT prerequisites
# ============================================================
echo "--- Section 1: APT prerequisites ---"
apt-get update -y
apt-get install -y \
    redis-server \
    postgresql \
    postgresql-contrib \
    rabbitmq-server \
    python3-venv \
    python3-dev

# ============================================================
# 2. PostgreSQL configuration
# ============================================================
echo "--- Section 2: PostgreSQL configuration ---"

# Relax auth for local connections (single-user VM on private vnet)
PG_HBA=$(find /etc/postgresql -name pg_hba.conf -print -quit 2>/dev/null)
if [ -n "${PG_HBA}" ]; then
    sed -i 's/peer/trust/g; s/scram-sha-256/trust/g' "${PG_HBA}"
    systemctl restart postgresql
fi

# Wait for PostgreSQL readiness
for _i in $(seq 1 10); do
    pg_isready -q 2>/dev/null && break
    sleep 1
done

# Create firecrawl database
if pg_isready -q 2>/dev/null; then
    if ! psql -U postgres -lqt 2>/dev/null | grep -qw firecrawl; then
        createdb -U postgres firecrawl
        echo "Created firecrawl database"
    fi
fi

# ============================================================
# 3. Redis and RabbitMQ
# ============================================================
echo "--- Section 3: Redis and RabbitMQ ---"
systemctl enable --now redis-server
systemctl enable --now rabbitmq-server

# Wait for RabbitMQ readiness
for _i in $(seq 1 10); do
    rabbitmqctl status >/dev/null 2>&1 && break
    sleep 1
done

# ============================================================
# 4. Rust toolchain (required for firecrawl-rs napi build)
# ============================================================
echo "--- Section 4: Rust toolchain ---"
if [ ! -f /root/.cargo/bin/cargo ]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --no-modify-path
fi
export PATH="/root/.cargo/bin:${PATH}"
echo "Rust: $(cargo --version 2>/dev/null || echo 'not available')"

# ============================================================
# 5. SearXNG installation
# ============================================================
echo "--- Section 5: SearXNG installation ---"

if [ ! -d /opt/searxng ]; then
    git clone --depth=1 https://github.com/searxng/searxng.git /opt/searxng
fi

if [ ! -d /opt/searxng/venv ]; then
    python3 -m venv /opt/searxng/venv
    /opt/searxng/venv/bin/pip install -U pip setuptools wheel
    # msgspec must be installed BEFORE the editable install
    /opt/searxng/venv/bin/pip install msgspec pyyaml typing-extensions pybind11
    /opt/searxng/venv/bin/pip install --use-pep517 --no-build-isolation -e /opt/searxng
fi

# SearXNG settings
mkdir -p /opt/searxng/etc
SEARXNG_SECRET=$(openssl rand -hex 32)
cat > /opt/searxng/etc/settings.yml << SEARXNG_SETTINGS
use_default_settings:
  engines:
    keep_only:
      - google
      - duckduckgo
      - startpage
      - wikipedia
      - aol
      - bing
      - mojeek
      - qwant

general:
  instance_name: "SearXNG"
  debug: false

server:
  bind_address: "127.0.0.1"
  port: 8888
  secret_key: "${SEARXNG_SECRET}"
  limiter: false
  image_proxy: false

search:
  safe_search: 0
  autocomplete: ""
  formats:
    - html
    - json

ui:
  static_use_hash: true

enabled_plugins:
  - Hash plugin
  - Self Information
  - Tracker URL remover
SEARXNG_SETTINGS

# SearXNG systemd service
cat > /etc/systemd/system/searxng.service << 'SEARXNG_SVC'
[Unit]
Description=SearXNG Metasearch Engine
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/searxng
Environment=SEARXNG_SETTINGS_PATH=/opt/searxng/etc/settings.yml
ExecStart=/opt/searxng/venv/bin/python -m searx.webapp
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SEARXNG_SVC

echo "SearXNG installed"

# ============================================================
# 6. Firecrawl build from source
# ============================================================
echo "--- Section 6: Firecrawl build from source ---"

if [ ! -d /opt/firecrawl ]; then
    git clone --depth=1 https://github.com/firecrawl/firecrawl.git /opt/firecrawl
fi

# Build API
if [ ! -d /opt/firecrawl/apps/api/dist ]; then
    echo "Building Firecrawl API..."
    cd /opt/firecrawl/apps/api
    pnpm install --ignore-scripts

    # Rust native bindings
    echo "Building firecrawl-rs native bindings (this takes ~2 minutes)..."
    cd /opt/firecrawl/apps/api/node_modules/@mendable/firecrawl-rs
    npx napi build --platform --release

    # TypeScript compile
    cd /opt/firecrawl/apps/api
    npx tsc
    echo "Firecrawl API built"
fi

# Build Playwright service
if [ ! -d /opt/firecrawl/apps/playwright-service-ts/dist ]; then
    echo "Building Playwright service..."
    cd /opt/firecrawl/apps/playwright-service-ts
    pnpm install --ignore-scripts
    npx tsc

    # Install Chromium browser
    PLAYWRIGHT_BROWSERS_PATH=/opt/firecrawl/.playwright npx playwright install chromium
    PLAYWRIGHT_BROWSERS_PATH=/opt/firecrawl/.playwright npx playwright install-deps chromium 2>/dev/null || true
    echo "Playwright service built"
fi

# Remove .git to save space
rm -rf /opt/firecrawl/.git

# ============================================================
# 7. Load database schema
# ============================================================
echo "--- Section 7: Database schema ---"

if pg_isready -q 2>/dev/null; then
    # Check if schema already loaded (nuq_jobs table exists)
    if ! psql -U postgres -d firecrawl -c "SELECT 1 FROM nuq_jobs LIMIT 0" 2>/dev/null; then
        if [ -f /opt/firecrawl/apps/nuq-postgres/nuq.sql ]; then
            # Strip pg_cron extension references (not available, only for maintenance)
            sed 's/CREATE EXTENSION.*pg_cron.*//g' /opt/firecrawl/apps/nuq-postgres/nuq.sql \
                | psql -U postgres -d firecrawl 2>&1 || true
            echo "Database schema loaded"
        fi
    else
        echo "Database schema already loaded"
    fi
fi

# ============================================================
# 8. Firecrawl environment file
# ============================================================
echo "--- Section 8: Environment file ---"

cat > /etc/firecrawl.env << FCENV
REDIS_URL=redis://localhost:6379
REDIS_RATE_LIMIT_URL=redis://localhost:6379
PLAYWRIGHT_MICROSERVICE_URL=http://localhost:3000
DATABASE_URL=postgresql://postgres@localhost:5432/firecrawl
NUQ_DATABASE_URL=postgresql://postgres@localhost:5432/firecrawl
NUQ_RABBITMQ_URL=amqp://localhost:5672
USE_DB_AUTHENTICATION=false
SEARXNG_ENDPOINT=http://localhost:8888
OPENAI_API_KEY=local-vllm
OPENAI_BASE_URL=${MEDIUM_LLM_BASE_URL}
MODEL_NAME=${MEDIUM_LLM_MODEL}
PLAYWRIGHT_BROWSERS_PATH=/opt/firecrawl/.playwright
NUM_WORKERS_PER_QUEUE=4
FCENV

chmod 644 /etc/firecrawl.env

# ============================================================
# 9. systemd service units
# ============================================================
echo "--- Section 9: systemd service units ---"

# Firecrawl Playwright service (port 3000)
cat > /etc/systemd/system/firecrawl-playwright.service << 'FC_SVC'
[Unit]
Description=Firecrawl Playwright Microservice
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/firecrawl/apps/playwright-service-ts
EnvironmentFile=/etc/firecrawl.env
Environment=PORT=3000
ExecStart=/usr/bin/node dist/api.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
FC_SVC

# Firecrawl API (port 3002)
cat > /etc/systemd/system/firecrawl-api.service << 'FC_SVC'
[Unit]
Description=Firecrawl API Server
After=network.target redis-server.service postgresql.service rabbitmq-server.service firecrawl-playwright.service searxng.service
Requires=redis-server.service postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/firecrawl/apps/api
EnvironmentFile=/etc/firecrawl.env
Environment=PORT=3002
Environment=HOST=0.0.0.0
ExecStart=/usr/bin/node dist/src/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
FC_SVC

# Firecrawl NuQ Prefetch Worker (port 3006)
cat > /etc/systemd/system/firecrawl-prefetch-worker.service << 'FC_SVC'
[Unit]
Description=Firecrawl NuQ Prefetch Worker
After=firecrawl-api.service

[Service]
Type=simple
WorkingDirectory=/opt/firecrawl/apps/api
EnvironmentFile=/etc/firecrawl.env
Environment=NUQ_PREFETCH_WORKER_PORT=3006
ExecStart=/usr/bin/node dist/src/services/worker/nuq-prefetch-worker.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
FC_SVC

# Firecrawl NuQ Scrape Worker (port 3005)
cat > /etc/systemd/system/firecrawl-scrape-worker.service << 'FC_SVC'
[Unit]
Description=Firecrawl NuQ Scrape Worker
After=firecrawl-api.service

[Service]
Type=simple
WorkingDirectory=/opt/firecrawl/apps/api
EnvironmentFile=/etc/firecrawl.env
Environment=NUQ_WORKER_PORT=3005
ExecStart=/usr/bin/node dist/src/services/worker/nuq-worker.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
FC_SVC

# Firecrawl Extract Worker
cat > /etc/systemd/system/firecrawl-extract-worker.service << 'FC_SVC'
[Unit]
Description=Firecrawl Extract Worker
After=firecrawl-api.service

[Service]
Type=simple
WorkingDirectory=/opt/firecrawl/apps/api
EnvironmentFile=/etc/firecrawl.env
ExecStart=/usr/bin/node dist/src/services/extract-worker.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
FC_SVC

systemctl daemon-reload

# Enable and start all services
systemctl enable --now searxng.service
systemctl enable --now firecrawl-playwright.service
sleep 2
systemctl enable --now firecrawl-api.service
sleep 2
systemctl enable --now firecrawl-prefetch-worker.service
systemctl enable --now firecrawl-scrape-worker.service
systemctl enable --now firecrawl-extract-worker.service

echo "All systemd services enabled and started"

# ============================================================
# 10. Convenience scripts
# ============================================================
echo "--- Section 10: Convenience scripts ---"

# check-firecrawl — health check for all services
cat > /usr/local/bin/check-firecrawl << 'CHECKSCRIPT'
#!/bin/bash
source /etc/profile.d/llm-endpoints.sh 2>/dev/null || true
echo "=== Firecrawl + SearXNG Service Status ==="
echo ""
echo "--- Infrastructure ---"
for svc in redis-server postgresql rabbitmq-server; do
    status=$(systemctl is-active $svc 2>/dev/null)
    printf "  %-30s %s\n" "$svc:" "$status"
done
echo ""
echo "--- SearXNG ---"
printf "  %-30s %s\n" "searxng:" "$(systemctl is-active searxng 2>/dev/null)"
echo -n "  SearXNG health:              "
curl -sf --max-time 3 "http://localhost:8888/search?q=test&format=json" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'OK ({len(d[\"results\"])} results)')" 2>/dev/null \
    || echo "FAIL"
echo ""
echo "--- Firecrawl ---"
for svc in firecrawl-playwright firecrawl-api firecrawl-prefetch-worker firecrawl-scrape-worker firecrawl-extract-worker; do
    status=$(systemctl is-active $svc 2>/dev/null)
    printf "  %-30s %s\n" "$svc:" "$status"
done
echo -n "  API health:                  "
curl -sf --max-time 3 http://localhost:3002/ \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if d.get('message')=='Firecrawl API' else 'FAIL')" 2>/dev/null \
    || echo "FAIL"
echo -n "  Playwright health:           "
curl -sf --max-time 3 http://localhost:3000/health \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'OK ({d[\"status\"]})')" 2>/dev/null \
    || echo "FAIL"
CHECKSCRIPT
chmod +x /usr/local/bin/check-firecrawl

# firecrawl-logs — tail all service logs
cat > /usr/local/bin/firecrawl-logs << 'LOGSCRIPT'
#!/bin/bash
exec journalctl -f \
    -u searxng \
    -u firecrawl-playwright \
    -u firecrawl-api \
    -u firecrawl-prefetch-worker \
    -u firecrawl-scrape-worker \
    -u firecrawl-extract-worker \
    "$@"
LOGSCRIPT
chmod +x /usr/local/bin/firecrawl-logs

# ============================================================
# 11. Add env vars to profile
# ============================================================
echo "--- Section 11: Environment variables ---"

# Append Firecrawl/SearXNG URLs if not already present
if ! grep -q FIRECRAWL_API_URL /etc/profile.d/llm-endpoints.sh 2>/dev/null; then
    cat >> /etc/profile.d/llm-endpoints.sh << 'ENVEOF'
export FIRECRAWL_API_URL="http://localhost:3002"
export SEARXNG_API_URL="http://localhost:8888"
ENVEOF
    echo "Added FIRECRAWL_API_URL and SEARXNG_API_URL to /etc/profile.d/llm-endpoints.sh"
fi

# ============================================================
# 12. Health check validation
# ============================================================
echo "--- Section 12: Health check validation ---"

sleep 3

PASS=0
FAIL=0

check_svc() {
    if systemctl is-active "$1" >/dev/null 2>&1; then
        echo "  [OK]   $1"
        PASS=$((PASS + 1))
    else
        echo "  [MISS] $1"
        FAIL=$((FAIL + 1))
    fi
}

for svc in redis-server postgresql rabbitmq-server searxng firecrawl-playwright firecrawl-api firecrawl-prefetch-worker firecrawl-scrape-worker firecrawl-extract-worker; do
    check_svc "$svc"
done

echo ""
echo "  API endpoint:     $(curl -sf --max-time 5 http://localhost:3002/ 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("message","FAIL"))' 2>/dev/null || echo 'FAIL')"
echo "  Playwright:       $(curl -sf --max-time 5 http://localhost:3000/health 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status","FAIL"))' 2>/dev/null || echo 'FAIL')"
echo ""
echo "Services: ${PASS} active, ${FAIL} failed"

echo "=== Firecrawl Setup Completed: $(date) ==="
