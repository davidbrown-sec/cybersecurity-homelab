# Findings: Authentik SSO + NPM Forward-Auth Integration

**Date:** 2026-07-19
**Category:** Identity & Access Management / Reverse Proxy Configuration
**Systems:** Authentik (`<REDACTED>`), Nginx Proxy Manager (`<REDACTED>`), Proxmox VE, Pi-hole

## Summary

Deployed Authentik as a centralized SSO layer for the homelab, integrated via two distinct patterns:

1. **Native OIDC** — Proxmox VE, which supports OpenID Connect realms directly. Full SSO: one login grants a real, permission-scoped Proxmox session.
2. **Forward-auth via NPM** — Pi-hole, which has no native SSO support. Authentik gates *network access* to the login page via nginx's `auth_request` module; Pi-hole's own password prompt still appears after the SSO check passes.

Both integrations required non-trivial troubleshooting. The root causes are documented below because they generalize to other Authentik deployments.

---

## Part 1: Proxmox OIDC Integration

### Issue 1 — Client ID Error

**Symptom:** Authentik's authorize endpoint returned "Client ID Error: The client identifier (client_id) is missing or invalid" immediately after clicking Proxmox's OIDC login button.

**Root cause:** Manual transcription error — a lowercase `l` was mistaken for a capital `I` when the Client ID was copied into Proxmox's realm config field. The value looked visually correct in a monospace font but wasn't a byte-for-byte match.

**Fix:** Re-copied the Client ID directly from Authentik's provider page (select-all, copy) rather than typing/reading it manually.

**Lesson:** Any manually transcribed secret with ambiguous characters (`l`/`I`/`1`, `0`/`O`) should be copy-pasted end-to-end, never re-typed, and verified via the actual outbound request (browser network tab or a raw `curl` to the authorize endpoint) rather than by eye.

### Issue 2 — Redirect URI Error

**Symptom:** After fixing Issue 1, the flow progressed further but failed with "Redirect URI Error: The request fails due to a missing, invalid, or mismatching redirection URI."

**Root cause:** Proxmox's actual outbound `redirect_uri` parameter (visible in the full authorize-endpoint URL) had no trailing slash. Authentik's provider had the Redirect URI configured in **Strict** mode with a trailing slash. Strict mode requires an exact character-for-character match.

**Fix:** Removed the trailing slash from Authentik's Redirect URI entry to match what Proxmox actually sends.

**Lesson:** When debugging OIDC redirect mismatches, inspect the literal outbound `redirect_uri` query parameter rather than assuming what an application "should" send. Different OIDC clients are inconsistent about trailing slashes.

### Issue 3 — Username too long (74 > 64)

**Symptom:** Login flow completed (redirect, consent, callback all succeeded), but Proxmox rejected the session with: `openid authentication failure; msg=user name '<64+ char hash>@authentik' is too long (74 > 64)`.

**Root cause:** Authentik's default OIDC `sub` claim is a hashed, opaque user identifier — typically 40-64+ characters. Proxmox usernames (including the `@realm` suffix) are hard-capped at 64 characters total. The hash overflowed the limit.

**Investigation:** Checked whether Proxmox exposes a `username-claim` option to select a shorter claim (e.g. `email` or `preferred_username`) instead of `sub`. Confirmed via `pvesh usage /access/domains/{realm} --verbose` that **no such option exists in Proxmox's OIDC realm schema at all** — this rules out a Proxmox-side config fix entirely.

**Fix:** The correct fix lives on the Authentik side: the OAuth2/OIDC provider has a **Subject mode** setting (under Advanced protocol settings) that controls what value populates the `sub` claim. Changed from the default (hashed user ID) to **"Based on the User's username"**, which produces a short, human-readable value well under the 64-character cap.

**Lesson:** Not every OIDC-related problem is fixable on the relying-party (Proxmox) side — sometimes the correct intervention point is the identity provider's claim-generation config. Confirming the absence of an option via the actual CLI/API schema (rather than assuming it must exist somewhere) saved significant time.

---

## Part 2: Pi-hole Forward-Auth via NPM

### Architecture

Authentik's Proxy Provider, in "Forward auth (single application)" mode, assigned to the built-in Embedded Outpost. NPM's `auth_request` nginx module calls Authentik's `/outpost.goauthentik.io/auth/nginx` endpoint before proxying to Pi-hole; a 401 from that endpoint triggers a redirect to Authentik's login flow instead of reaching Pi-hole.

### Issue 4 — Authentik's own reference snippet is broken with NPM

**Symptom:** Following Authentik's documented nginx snippet (as surfaced in its own UI) produced a plain, unstyled `401 Authorization Required` / `openresty` error page — not even Authentik's branded error page — meaning the request was reaching Pi-hole directly and Pi-hole's own API was rejecting it, rather than being intercepted by Authentik at all.

**Root cause:** Confirmed via community sources (a third-party Authentik+NPM integration writeup, corroborated independently) that Authentik's default `error_page 401 = /outpost.goauthentik.io/start?rd=$request_uri;` directive does not reliably work when NPM is the reverse proxy — the redirect silently fails to fire under certain NPM template/config-injection conditions.

**Fix:** Replaced the direct `error_page` path with a **named internal location**:
```nginx
location @goauthentik_proxy_signin {
    internal;
    add_header Set-Cookie $auth_cookie;
    return 302 /outpost.goauthentik.io/start?rd=$request_uri;
}
```
and pointed `error_page 401` at that named location instead of a literal path. Also added `proxy_buffers 8 16k; proxy_buffer_size 32k;` and `port_in_redirect off;` per the same community-verified pattern.

**Lesson:** Vendor-provided reference configs for reverse-proxy integrations should be treated as a starting point, not a guarantee — especially for less common proxy targets (NPM vs. the more commonly documented Traefik/Kubernetes-ingress patterns). Cross-checking against real-world community reports of the same integration surfaced the fix faster than continued isolated debugging.

### Issue 5 — "mismatched session ID" / 400 on callback

**Symptom:** Even after Issue 4's fix, the OIDC callback (`/outpost.goauthentik.io/callback?...`) intermittently returned `HTTP 400` with no body, and Authentik's server logs showed `"event":"mismatched session ID"` with an empty `"should"` field — indicating Authentik expected a session cookie on the callback request and received none.

**Root cause analysis:** Verified via direct `curl` testing (bypassing the browser, forcing SNI with `--resolve`) that the `/outpost.goauthentik.io/*` location was correctly routing to Authentik (confirmed by the `Set-Cookie: authentik_proxy_...` response header on a simple `/auth/nginx` request). The issue was specific to the callback URL, which carries a long JWT in its `state=` query parameter. Testing confirmed the URL length/header size was tripping an nginx-level limit before the request even reached the location-routing logic — `HTTP ERROR 400` with `server: openresty` and no Authentik-branded response body, distinct from a proper Authentik-issued 400.

**Fix:** Added a custom top-level nginx include:
```nginx
# ~/npm/data/nginx/custom/http_top.conf
large_client_header_buffers 4 32k;
```
NPM only picks up custom top-level directives from specific expected filenames (confirmed via `nginx -T | grep custom/` to enumerate the exact include paths NPM's base config expects — `http_top.conf` was correct, but the file initially failed to write due to root-owned `data/` directory permissions requiring `sudo`).

**Lesson:** Long OIDC state parameters (common when the identity provider embeds session/redirect metadata as a signed JWT) can exceed default nginx header buffer limits. This manifests as a bare, un-branded 400 — worth checking `large_client_header_buffers` whenever a callback URL with a large query string fails at the proxy layer before reaching the application.

### Issue 6 — Pi-hole has no native SSO/trusted-header support (confirmed limitation, not a bug)

**Symptom:** After all of the above fixes, forward-auth worked correctly — an unauthenticated request to Pi-hole's login page is now properly intercepted and redirected to Authentik's login/consent flow. However, after completing SSO, Pi-hole's *own* password prompt still appears; there is no automatic passthrough into an authenticated Pi-hole session.

**Root cause:** Confirmed via Pi-hole's own upstream feature-request tracker (open, unimplemented as of this writing) that Pi-hole's web interface has a single shared admin password with no support for trusting an externally-authenticated identity — no `Remote-User`-style header integration, no basic-auth passthrough option. This is a genuine product gap, not a misconfiguration on the homelab side.

**Decision:** Left the integration as **double-gated** — Authentik controls network-level access to the login page (meaningful defense-in-depth, since unauthorized devices on the LAN can no longer even reach Pi-hole's password prompt), and Pi-hole's native password remains as a second factor. The alternative (disabling Pi-hole's password to force a single-login experience) was rejected as a worse security tradeoff for a marginal convenience gain.

---

## Reusable NPM Forward-Auth Config (verified working)

For any future service integrated the same way:

**Server-level (Advanced tab):**
```nginx
proxy_buffers 8 16k;
proxy_buffer_size 32k;
port_in_redirect off;

location /outpost.goauthentik.io {
    proxy_pass              http://<REDACTED>:9000/outpost.goauthentik.io;
    proxy_set_header        Host $host;
    proxy_set_header        X-Original-URL $scheme://$http_host$request_uri;
    add_header               Set-Cookie $auth_cookie;
    auth_request_set        $auth_cookie $upstream_http_set_cookie;
    proxy_pass_request_body off;
    proxy_set_header        Content-Length "";
}

location @goauthentik_proxy_signin {
    internal;
    add_header Set-Cookie $auth_cookie;
    return 302 /outpost.goauthentik.io/start?rd=$request_uri;
}
```

**Per-location (Custom Locations tab, the `/` location's own Advanced box):**
```nginx
auth_request /outpost.goauthentik.io/auth/nginx;
error_page 401 = @goauthentik_proxy_signin;

auth_request_set $auth_cookie $upstream_http_set_cookie;
add_header Set-Cookie $auth_cookie;

auth_request_set $authentik_username $upstream_http_x_authentik_username;
proxy_set_header X-authentik-username $authentik_username;
```

**Required one-time server-wide fix** (already applied on the NPM host):
```nginx
# ~/npm/data/nginx/custom/http_top.conf
large_client_header_buffers 4 32k;
```

---

## MITRE / Detection Engineering Relevance

While this was an infrastructure/IAM project rather than a detection-engineering exercise, it's directly relevant to identity-focused detection work:
- The Authentik System Log (`docker compose logs server`) provides structured JSON events for authentication successes/failures, session mismatches, and callback errors — a good analog to what a SOC analyst would triage from Okta/Entra ID/Ping logs in a production environment
- The troubleshooting process itself (isolating whether a failure is client-side, proxy-side, or IdP-side via targeted `curl` requests with controlled headers) mirrors the methodology used in investigating real authentication anomalies
