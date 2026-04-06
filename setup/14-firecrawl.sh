#!/bin/bash
# ==============================================================================
# SECTION 14: FIRECRAWL (self-hosted web scraper)
# ==============================================================================

# Dependencies
apt-get install -y redis-server postgresql postgresql-contrib

# Start Redis
systemctl enable redis-server
systemctl start redis-server

# Clone Firecrawl
git clone --depth 1 https://github.com/mendableai/firecrawl.git /opt/firecrawl 2>/dev/null || true

if [ -d /opt/firecrawl ]; then
  cd /opt/firecrawl/apps/api
  pnpm install 2>/dev/null || npm install 2>/dev/null || true

  # Create systemd service
  cat > /etc/systemd/system/firecrawl.service <<'SYSTEMD'
[Unit]
Description=Firecrawl Web Scraper API
After=network.target redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/firecrawl/apps/api
ExecStart=/usr/bin/npx tsx src/index.ts
Environment=PORT=3002
Environment=REDIS_URL=redis://localhost:6379
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD
  systemctl daemon-reload
  systemctl enable firecrawl.service
  echo "Firecrawl installed at /opt/firecrawl (port 3002)"
else
  echo "WARNING: Firecrawl clone failed"
fi
