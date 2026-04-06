#!/bin/bash
# ==============================================================================
# SECTION 9: BROWSER AUTOMATION
# ==============================================================================

# Chromium headless
apt-get install -y chromium-browser 2>/dev/null || apt-get install -y chromium 2>/dev/null || true

# Playwright (Python) + browsers
/opt/vllm-env/bin/pip install playwright playwright-stealth
/opt/vllm-env/bin/python -m playwright install --with-deps chromium 2>/dev/null || true

# Playwright (Node.js)
npm install -g playwright @playwright/cli 2>/dev/null || true
npx playwright install chromium 2>/dev/null || true

# Puppeteer ecosystem (for advanced browser automation)
npm install -g puppeteer puppeteer-extra puppeteer-extra-plugin-stealth 2>/dev/null || true

# Lynx + w3m (terminal browsers for text-only scraping)
apt-get install -y lynx w3m

echo "Browser automation installed: Chromium, Playwright, Puppeteer, terminal browsers"
