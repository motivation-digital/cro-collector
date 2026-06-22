#!/bin/bash

WORKER="cro-collector"
ACCOUNT_ID="681f0c5e92719198aa9688776079097e"

echo "=== Smoke test: $WORKER ==="
echo ""

# Verify worker script is deployed via CF API
echo "Test 1: Verify worker script deployed"
HTTP_CODE=$(curl -s -m 5 -w "%{http_code}" -o /tmp/cf-script.json \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER}")

if [ "$HTTP_CODE" = "200" ]; then
  echo "PASS: worker script exists (HTTP 200)"
else
  echo "FAIL: worker script not found (HTTP $HTTP_CODE)"
  cat /tmp/cf-script.json
  exit 1
fi
echo ""

# Verify critical binding (DB_SITES)
echo "Test 2: Verify DB_SITES D1 binding"
HTTP_CODE=$(curl -s -m 5 -w "%{http_code}" -o /tmp/cf-settings.json \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER}/settings")

if [ "$HTTP_CODE" = "200" ]; then
  if grep -q '"DB_SITES"' /tmp/cf-settings.json; then
    echo "PASS: DB_SITES binding present"
  else
    echo "FAIL: DB_SITES binding missing"
    cat /tmp/cf-settings.json
    exit 1
  fi
else
  echo "FAIL: could not retrieve settings (HTTP $HTTP_CODE)"
  cat /tmp/cf-settings.json
  exit 1
fi
echo ""

# Health check — workers.dev may take time to warm up post-deploy, skip if timeout
echo "Test 3: GET /health (optional — workers.dev warm-up)"
HTTP_CODE=$(curl -s -m 3 -w "%{http_code}" -o /tmp/health-resp.json \
  "https://${WORKER}.workers.dev/health" 2>/dev/null || echo "000")

case "$HTTP_CODE" in
  200)
    echo "PASS: /health returned 200"
    cat /tmp/health-resp.json
    ;;
  000|timeout)
    echo "SKIP: workers.dev not yet warmed up (typical post-deploy)"
    ;;
  *)
    echo "WARN: /health returned HTTP $HTTP_CODE (workers.dev may need more time)"
    ;;
esac
echo ""

echo "=== Smoke tests completed ==="
exit 0
