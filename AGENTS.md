# cro-collector

Server-side GA4 Measurement Protocol collector for the CRO Framework (AGI-9000437). Accepts funnel events from front-end (page_view, health_index_start, health_index_complete, begin_checkout, purchase, member_activate) and forwards them to Google Analytics 4. Multi-tenant via brand key lookup in sites D1.

Deploys to: `cro-collector` (workers.dev, no route)
Repo: https://github.com/motivation-digital/lifecycle

## ⛔ Must not change

- The POST /{brand}/event handler contract (called by dbc-site + dbc-index funnel; stripe-payments calls to purchase event via service binding)
- The GA4 Measurement Protocol payload structure
- Event type enum (page_view, health_index_start, health_index_complete, begin_checkout, purchase, member_activate)
- Consent gate logic (blocks all events until consent is confirmed)

## Current state

BUILT & DEPLOYED (AGI-9000437, 2026-06-22). Worker is live; no events sent until:
1. Google Tag Gateway is enabled on dreambody.club zone (GA4 data ingestion begins)
2. Consent gate is wired to TrustCentre module (currently fail-safe blocks all)

The stripe-payments worker has the CRO_COLLECTOR service binding configured and calls it on purchase.

## Endpoints

| Method | Path | Purpose | Auth |
| --- | --- | --- | --- |
| POST | /{brand}/event | Accept and forward funnel event to GA4 | public (visitor client_id in payload) |
| GET | /health | Liveness check | public |

## D1 bindings

| Binding | Database | Access |
| --- | --- | --- |
| DB_SITES | sites (shared) | read (brand registry) |

## Secrets Store bindings

| Binding | Secret | Purpose |
| --- | --- | --- |
| GA4_API_SECRET | GA4_API_SECRET | Google Analytics 4 Measurement Protocol API secret |

## Consent gate (currently fail-safe, wired in future)

TrustCentre module (AGI-9000260) or Zaraz Consent bridge (AGI-9000074). For now:
- Events are blocked by default (no consent module live)
- Testing: pass `X-Consent-Analytics: true` header to override

## Rules (inline — full rules in lifecycle)

- Rule 1: Confirm repo first. `pwd` and `git remote -v` before anything.
- Rule 2: Read before touching. Check AGENTS.md and current main.
- Rule 9: Trace all consumers before removing any parameter, endpoint, or field.
- Rule 14: Every session is referenced by its ClickUp task ID (e.g. `LCE-10000040`).
