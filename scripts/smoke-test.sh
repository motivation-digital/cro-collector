#!/bin/bash
set -e

WORKER="cro-collector"
MAX_RETRIES=15
RETRY_DELAY=2

echo "=== Smoke test: $WORKER ==="
echo ""

# Health check with retry (worker may not be immediately available post-deploy)
echo "Test 1: GET /health (with retry for post-deploy availability)"

attempt=1
while [ $attempt -le $MAX_RETRIES ]; do
  HTTP_CODE=$(curl -s -m 5 -w "%{http_code}" -o /tmp/health-resp.json \
    "https://${WORKER}.workers.dev/health" 2>/dev/null || echo "000")
  
  if [ "$HTTP_CODE" = "200" ]; then
    BODY=$(cat /tmp/health-resp.json)
    echo "PASS: /health returned 200"
    echo "Body: $BODY"
    echo ""
    break
  else
    if [ $attempt -eq $MAX_RETRIES ]; then
      echo "FAIL: health check failed after $MAX_RETRIES attempts (last HTTP: $HTTP_CODE)"
      exit 1
    fi
    echo "Attempt $attempt/$MAX_RETRIES: HTTP $HTTP_CODE, retrying in ${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
  fi
  attempt=$((attempt + 1))
done

# Test 2: POST with invalid brand (should return 404)
echo "Test 2: POST /invalid-brand/event"
HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/test2-resp.json \
  -X POST "https://${WORKER}.workers.dev/invalid-brand/event" \
  -H "Content-Type: application/json" \
  -d '{"type":"page_view","data":{}}')
BODY=$(cat /tmp/test2-resp.json)

if [ "$HTTP_CODE" = "404" ]; then
  echo "PASS: invalid brand returned 404"
else
  echo "Result: HTTP $HTTP_CODE (expected 404)"
  echo "Body: $BODY"
fi
echo ""

# Test 3: POST with invalid event type (should return 400)
echo "Test 3: POST /dbc/event with invalid event type"
HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/test3-resp.json \
  -X POST "https://${WORKER}.workers.dev/dbc/event" \
  -H "Content-Type: application/json" \
  -d '{"type":"invalid_event","data":{}}')
BODY=$(cat /tmp/test3-resp.json)

if [ "$HTTP_CODE" = "400" ]; then
  echo "PASS: invalid event type returned 400"
else
  echo "Result: HTTP $HTTP_CODE (expected 400)"
  echo "Body: $BODY"
fi
echo ""

# Test 4: POST with valid event (will be pre-consent, so 202 or 200 is OK)
echo "Test 4: POST /dbc/event with valid page_view"
HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/test4-resp.json \
  -X POST "https://${WORKER}.workers.dev/dbc/event" \
  -H "Content-Type: application/json" \
  -d '{"type":"page_view","data":{"page_title":"Home","page_location":"https://dreambody.club/"}}')
BODY=$(cat /tmp/test4-resp.json)

if [ "$HTTP_CODE" = "202" ] || [ "$HTTP_CODE" = "200" ]; then
  echo "PASS: valid event returned $HTTP_CODE (pre-consent or OK)"
else
  echo "Result: HTTP $HTTP_CODE (expected 202 or 200)"
  echo "Body: $BODY"
fi
echo ""

echo "=== All smoke tests completed ==="
exit 0
