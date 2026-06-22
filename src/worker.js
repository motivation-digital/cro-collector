/**
 * cro-collector: GA4 Measurement Protocol server-side collector
 *
 * Receives front-end funnel events → forwards to GA4.
 * Multi-tenant via brand key in sites D1 registry.
 * Gated on consent (TrustCentre module or Zaraz Consent).
 *
 * Accepts: POST /{brand}/event
 * Payload: { type: 'page_view'|'health_index_start'|..., data: {...} }
 *
 * CRO Framework (AGI-9000437): measurement pipeline.
 * Tag Gateway (step 1) must be live before events flow.
 */

/**
 * Event taxonomy (from CRO runbook, doc 2bn9p-102232)
 * page_view | health_index_start | health_index_complete | begin_checkout | purchase | member_activate
 */

// Map event types to GA4 event names
const EVENT_TYPE_MAP = {
  page_view: 'page_view',
  health_index_start: 'health_index_start',
  health_index_complete: 'health_index_complete',
  begin_checkout: 'begin_checkout',
  purchase: 'purchase',
  member_activate: 'member_activate',
};

/**
 * Resolve brand from request — infer from path or Host header
 */
async function resolveBrand(request, env) {
  const url = new URL(request.url);
  const pathSegments = url.pathname.split('/').filter(Boolean);

  // POST /{brand}/event → pathSegments[0] = brand
  const brandFromPath = pathSegments[0];
  if (brandFromPath && pathSegments[1] === 'event') {
    return brandFromPath;
  }

  // Fallback: infer from Host header (e.g., index.dreambody.club → dbc)
  const host = request.headers.get('Host') || '';
  if (host.includes('dreambody')) return 'dbc';
  if (host.includes('launchpad')) return 'lpd';
  if (host.includes('trustcenter')) return 'tc';
  if (host.includes('studio')) return 'std';

  return null;
}

/**
 * Look up brand in sites D1 → get Measurement ID and GA4 config
 */
async function getBrandConfig(brand, env) {
  if (!brand) return null;

  try {
    const row = await env.DB_SITES.prepare(
      'SELECT id, active FROM clients WHERE id = ? AND active = 1'
    )
      .bind(brand)
      .first();

    if (!row) return null;

    // For DBC: hardcoded Measurement ID (from cowork setup, 2026-06-22)
    // In multi-tenant future, store in clients table
    if (brand === 'dbc') {
      return {
        id: brand,
        measurement_id: 'G-KQH8EKYZ9L',
        ga4_endpoint: 'https://www.google-analytics.com/mp/collect',
      };
    }

    return { id: brand };
  } catch (err) {
    console.error(`[cro-collector] D1 lookup failed for brand ${brand}:`, err);
    return null;
  }
}

/**
 * Check consent status — currently fail-safe (blocks all events pre-consent)
 *
 * Wired to TrustCentre module (AGI-9000260) or Zaraz Consent bridge (AGI-9000074)
 * when consent architecture is ready. For now, event acceptance is gated by:
 * 1. A consent header passed in the request (e.g., X-Consent-Analytics: true)
 * 2. Or a service binding call (added later)
 *
 * Returns: true if allowed, false if pre-consent or denied (fail-safe default: false)
 */
async function checkConsent(request, visitorId, brand) {
  // Check for explicit consent header (testing/manual override)
  // Format: X-Consent-Analytics: true
  const consentHeader = request?.headers?.get('X-Consent-Analytics');
  if (consentHeader === 'true') {
    console.info(
      `[cro-collector] Consent granted via header for ${visitorId} on ${brand}`
    );
    return true;
  }

  // Fail-safe: block all events until consent module is wired
  console.info(
    `[cro-collector] Consent check: no analytics consent for ${visitorId} (module not yet wired)`
  );
  return false;
}

/**
 * Send event to GA4 Measurement Protocol
 *
 * GA4 API endpoint: POST https://www.google-analytics.com/mp/collect
 * Payload: { api_secret, measurement_id, client_id, events: [...] }
 */
async function sendToGA4(event, brand, visitorId, config, env) {
  if (!config || !config.measurement_id) {
    console.error(
      `[cro-collector] No Measurement ID for brand ${brand}; skipping GA4`
    );
    return { ok: false, error: 'no_measurement_id' };
  }

  try {
    const apiSecret = await env.GA4_API_SECRET.get();
    if (!apiSecret) {
      console.error('[cro-collector] GA4_API_SECRET not set');
      return { ok: false, error: 'no_api_secret' };
    }

    const eventName = EVENT_TYPE_MAP[event.type] || event.type;

    // GA4 Measurement Protocol payload
    // Reference: https://developers.google.com/analytics/devguides/collection/protocol/ga4
    const payload = {
      api_secret: apiSecret,
      measurement_id: config.measurement_id,
      client_id: visitorId,
      events: [
        {
          name: eventName,
          params: {
            // Standard GA4 params
            page_title: event.data?.page_title || '',
            page_location: event.data?.page_location || '',
            // Custom params for CRO events
            ...event.data,
          },
        },
      ],
    };

    const resp = await fetch(config.ga4_endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!resp.ok) {
      console.warn(
        `[cro-collector] GA4 returned HTTP ${resp.status} for event ${eventName}`
      );
      return { ok: false, error: `ga4_http_${resp.status}` };
    }

    return { ok: true };
  } catch (err) {
    console.error('[cro-collector] GA4 send error:', err);
    return { ok: false, error: 'fetch_error' };
  }
}

/**
 * Main request handler
 */
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Health check
    if (request.method === 'GET' && url.pathname === '/health') {
      return new Response(
        JSON.stringify({ ok: true, worker: 'cro-collector' }),
        { headers: { 'Content-Type': 'application/json' } }
      );
    }

    // POST /{brand}/event
    if (request.method !== 'POST') {
      return new Response(
        JSON.stringify({ error: 'method_not_allowed' }),
        { status: 405, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const pathSegments = url.pathname.split('/').filter(Boolean);
    if (pathSegments.length < 2 || pathSegments[1] !== 'event') {
      return new Response(
        JSON.stringify({ error: 'invalid_path' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    try {
      const brand = await resolveBrand(request, env);
      if (!brand) {
        return new Response(
          JSON.stringify({ error: 'brand_not_resolved' }),
          { status: 400, headers: { 'Content-Type': 'application/json' } }
        );
      }

      const brandConfig = await getBrandConfig(brand, env);
      if (!brandConfig) {
        return new Response(
          JSON.stringify({ error: 'brand_not_found' }),
          { status: 404, headers: { 'Content-Type': 'application/json' } }
        );
      }

      const body = await request.json();
      const eventType = body.type;
      const eventData = body.data || {};

      if (!eventType || !EVENT_TYPE_MAP[eventType]) {
        return new Response(
          JSON.stringify({ error: 'invalid_event_type' }),
          { status: 400, headers: { 'Content-Type': 'application/json' } }
        );
      }

      // Resolve visitor ID (from cookie, session, or request header)
      const visitorId =
        request.headers.get('X-Visitor-ID') ||
        eventData.client_id ||
        `visitor-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

      // Check consent before sending
      const allowed = await checkConsent(request, visitorId, brand);
      if (!allowed) {
        // Pre-consent: acknowledge but don't send to GA4
        console.info(
          `[cro-collector] Event ${eventType} blocked (pre-consent) for ${visitorId}`
        );
        return new Response(
          JSON.stringify({ ok: false, reason: 'pre_consent' }),
          { status: 202, headers: { 'Content-Type': 'application/json' } }
        );
      }

      // Send to GA4
      const result = await sendToGA4(
        { type: eventType, data: eventData },
        brand,
        visitorId,
        brandConfig,
        env
      );

      if (!result.ok) {
        console.warn(`[cro-collector] GA4 send failed: ${result.error}`);
      }

      return new Response(
        JSON.stringify({ ok: result.ok, event_type: eventType }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    } catch (err) {
      console.error('[cro-collector] request handler error:', err);
      return new Response(
        JSON.stringify({ error: 'internal_error', message: err.message }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }
  },
};
