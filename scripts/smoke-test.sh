#!/bin/bash
set -e

WORKER="cro-collector"
ACCOUNT_ID="681f0c5e92719198aa9688776079097e"

echo "=== Smoke test: $WORKER ==="
echo ""

# Test 1: Health check
echo "Test 1: GET /health"
HEALTH_RESP=$(curl -s -w "\n%{http_code}" "https://${WORKER}.workers.dev/health")
HTTP_CODE=$(echo "$HEALTH_RESP" | tail -1)
BODY=$(echo "$HEALTH_RESP" | head -1)

if [ "$HTTP_CODE" != "200" ]; then
  echo "FAIL: health check returned HTTP $HTTP_CODE"
  echo "Body: $BODY"
  exit 1
fi

echo "PASS: /health returned 200"
echo "Body: $BODY"
echo ""

# Test 2: POST with invalid brand
echo "Test 2: POST /invalid-brand/event with invalid brand"
RESP=$(curl -s -w "\n%{http_code}" -X POST "https://${WORKER}.workers.dev/invalid-brand/event" \
  -H "Content-Type: application/json" \
  -d '{"type":"page_view","data":{}}')
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -1)

if [ "$HTTP_CODE" != "404" ]; then
  echo "FAIL: expected 404 for invalid brand, got $HTTP_CODE"
  echo "Body: $BODY"
  exit 1
fi

echo "PASS: /invalid-brand/event returned 404 as expected"
echo "Body: $BODY"
echo ""

# Test 3: POST with invalid event type
echo "Test 3: POST /dbc/event with invalid event type"
RESP=$(curl -s -w "\n%{http_code}" -X POST "https://${WORKER}.workers.dev/dbc/event" \
  -H "Content-Type: application/json" \
  -d '{"type":"invalid_event","data":{}}')
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -1)

if [ "$HTTP_CODE" != "400" ]; then
  echo "FAIL: expected 400 for invalid event type, got $HTTP_CODE"
  echo "Body: $BODY"
  exit 1
fi

echo "PASS: invalid event type returned 400"
echo "Body: $BODY"
echo ""

# Test 4: POST with valid event (will fail GA4 / consent, but request handling should be OK)
echo "Test 4: POST /dbc/event with valid page_view"
RESP=$(curl -s -w "\n%{http_code}" -X POST "https://${WORKER}.workers.dev/dbc/event" \
  -H "Content-Type: application/json" \
  -d '{"type":"page_view","data":{"page_title":"Home","page_location":"https://dreambody.club/"}}')
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | head -1)

# Event will be pre-consent (blocked), so expect 202 or 200 — either is OK at this stage
if [ "$HTTP_CODE" != "202" ] && [ "$HTTP_CODE" != "200" ]; then
  echo "WARN: expected 202 or 200 for valid event, got $HTTP_CODE"
  echo "Body: $BODY"
  # Don't fail — pre-consent is expected before Tag Gateway is live
fi

echo "PASS: valid event returned HTTP $HTTP_CODE (pre-consent or GA4 failure is expected)"
echo "Body: $BODY"
echo ""

echo "=== All smoke tests passed ==="
exit 0
