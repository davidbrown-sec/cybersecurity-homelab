# Findings: Authentik SSO + Reverse Proxy Forward-Auth Integration

**Category:** Identity & Access Management / Reverse Proxy Configuration

## Summary

Deployed an identity provider (Authentik) as a centralized SSO layer for homelab services, integrated via two distinct patterns:

1. **Native OIDC** — Proxmox VE, which supports OpenID Connect realms directly. Full SSO: one login grants a real, permission-scoped session.
2. **Forward-auth via reverse proxy** — a DNS admin tool with no native SSO support. The identity provider gates *network access* to the login page via nginx's `auth_request` module; the tool's own password prompt still appears after the SSO check passes.

Both integrations required non-trivial troubleshooting. The root causes are documented below because they generalize to other Authentik-style deployments.

---

## Part 1: Proxmox OIDC Integration

### Issue 1 — Client ID Error

**Symptom:** Authentik's authorize endpoint returned "Client ID Error" immediately after clicking Proxmox's OIDC login button.

**Root cause:** Manual transcription error — a lowercase `l` was mistaken for a capital `I` when the Client ID was copied into Proxmox's realm config field.

**Fix:** Re-copied the Client ID directly (select-all, copy) rather than typing/reading it manually.

**Lesson:** Any manually transcribed secret with ambiguous characters (`l`/`I`/`1`, `0`/`O`) should be copy-pasted end-to-end and verified via the actual outbound request rather than by eye.

### Issue 2 — Redirect URI Error

**Symptom:** After fixing Issue 1, the flow failed with "Redirect URI Error."

**Root cause:** Proxmox's actual outbound `redirect_uri` parameter had no trailing slash. Authentik's provider had the Redirect URI configured in **Strict** mode with a trailing slash. Strict mode requires an exact character-for-character match.

**Fix:** Removed the trailing slash from Authentik's Redirect URI entry.

**Lesson:** When debugging OIDC redirect mismatches, inspect the literal outbound `redirect_uri` query parameter rather than assuming what an application "should" send.

### Issue 3 — Username too long (74 > 64)

**Symptom:** Login flow completed (redirect, consent, callback all succeeded), but Proxmox rejected the session with a "user name is too long (74 > 64)" error.

**Root cause:** Authentik's default OIDC `sub` claim is a hashed, opaque user identifier — typically 40-64+ characters. Proxmox usernames (including the `@realm` suffix) are hard-capped at 64 characters total.

**Investigation:** Confirmed via Proxmox's own CLI schema (`pvesh usage /access/domains/{realm} --verbose`) that **no option exists in Proxmox's OIDC realm config to select a shorter claim** — ruling out a Proxmox-side fix entirely.

**Fix:** The correct fix lives on the identity provider side: the OAuth2/OIDC provider's **Subject mode** setting (Advanced protocol settings), changed from the default (hashed user ID) to "Based on the User's username."

**Lesson:** Not every OIDC-related problem is fixable on the relying-party side — sometimes the correct intervention point is the identity provider's claim-generation config. Confirming the absence of an option via the actual CLI/API schema saved significant time versus continued guessing.

---

## Part 2: Forward-Auth via Reverse Proxy

### Architecture

Authentik's Proxy Provider, in "Forward auth (single application)" mode, assigned to the built-in Embedded Outpost. The reverse proxy's `auth_request` module calls Authentik's `/outpost.goauthentik.io/auth/nginx` endpoint before proxying to the target app; a 401 from that endpoint triggers a redirect to the login flow instead.

### Issue 4 — The vendor's own reference snippet is broken with this reverse proxy

**Symptom:** Following Authentik's documented nginx snippet produced a plain, unstyled 401 error — meaning the request reached the target app directly rather than being intercepted by Authentik at all.

**Root cause:** Confirmed via independent community reports that Authentik's default `error_page 401 = /outpost.goauthentik.io/start?rd=$request_uri;` directive does not reliably work with this particular reverse proxy — the redirect silently fails to fire under certain config-injection conditions.

**Fix:** Replaced the direct `error_page` path with a **named internal location**:
```nginx
location @goauthentik_proxy_signin {
    internal;
    add_header Set-Cookie $auth_cookie;
    return 302 /outpost.goauthentik.io/start?rd=$request_uri;
}
```
plus explicit `proxy_buffers`/`proxy_buffer_size` sizing and `port_in_redirect off;`.

**Lesson:** Vendor-provided reference configs for reverse-proxy integrations should be treated as a starting point, not a guarantee — especially for less commonly documented proxy targets. Cross-checking against real-world community reports of the same integration surfaced the fix faster than continued isolated debugging.

### Issue 5 — "mismatched session ID" / 400 on callback

**Symptom:** Even after Issue 4's fix, the OIDC callback intermittently returned HTTP 400 with no body, and server logs showed a "mismatched session ID" event with an empty expected-session field.

**Root cause:** Verified via direct `curl` testing (bypassing the browser, forcing SNI) that routing to the identity provider was correct in isolation. The issue was specific to the callback URL, which carries a long JWT in its `state=` parameter — long enough to trip an nginx-level header size limit before the request reached location-routing logic.

**Fix:** Added a custom top-level nginx include:
```nginx
large_client_header_buffers 4 32k;
```

**Lesson:** Long OIDC state parameters can exceed default nginx header buffer limits. This manifests as a bare, un-branded 400 — worth checking `large_client_header_buffers` whenever a callback URL with a large query string fails at the proxy layer before reaching the application.

### Issue 6 — Target app has no native SSO/trusted-header support (confirmed limitation, not a bug)

**Symptom:** After all fixes, forward-auth worked correctly — an unauthenticated request is properly intercepted and redirected to the login/consent flow. However, the target app's own password prompt still appears after SSO completes; there's no automatic passthrough.

**Root cause:** Confirmed via the target application's own upstream feature-request tracker (open, unimplemented) that it has a single shared admin password with no support for trusting an externally-authenticated identity.

**Decision:** Left the integration as **double-gated** — the identity provider controls network-level access to the login page (meaningful defense-in-depth, since unauthorized devices on the LAN can no longer even reach the app's password prompt), and the app's native password remains as a second factor. Disabling the app's password to force a single-login experience was rejected as a worse security tradeoff for a marginal convenience gain.

---

## Reusable Forward-Auth Config Pattern (verified working)

**Server-level:**
```nginx
proxy_buffers 8 16k;
proxy_buffer_size 32k;
port_in_redirect off;

location /outpost.goauthentik.io {
    proxy_pass              http://<identity-provider-internal-address>/outpost.goauthentik.io;
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

**Per-application location:**
```nginx
auth_request /outpost.goauthentik.io/auth/nginx;
error_page 401 = @goauthentik_proxy_signin;

auth_request_set $auth_cookie $upstream_http_set_cookie;
add_header Set-Cookie $auth_cookie;

auth_request_set $authentik_username $upstream_http_x_authentik_username;
proxy_set_header X-authentik-username $authentik_username;
```

**Required one-time server-wide fix:**
```nginx
large_client_header_buffers 4 32k;
```

---

## Detection Engineering Relevance

While this was an infrastructure/IAM project, it's directly relevant to identity-focused detection work:
- The identity provider's structured JSON event log (authentication successes/failures, session mismatches, callback errors) is a close analog to what a SOC analyst triages from Okta/Entra ID/Ping logs in production
- The troubleshooting methodology — isolating whether a failure is client-side, proxy-side, or IdP-side via targeted `curl` requests with controlled headers — mirrors the process used when investigating real authentication anomalies
