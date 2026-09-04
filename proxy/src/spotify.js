/**
 * The parts of the proxy worth testing: they take their dependencies as
 * arguments, so a test can drive them without a network or a real Worker.
 */

const TOKEN_URL = "https://accounts.spotify.com/api/token";
const SEARCH_URL = "https://api.spotify.com/v1/search";

/** Spotify rejects a `limit` above 10 for a Development Mode app registration. */
export const SEARCH_LIMIT = 10;

/** A query longer than this is not a search, it is someone probing. */
export const MAX_QUERY_LENGTH = 200;

/** Refresh a little early so a token cannot expire mid-flight. */
const EXPIRY_SKEW_SECONDS = 60;

export class TokenStore {
  /**
   * @param {{ clientID: string, clientSecret: string, fetch?: typeof globalThis.fetch, now?: () => number }} options
   */
  constructor({ clientID, clientSecret, fetch = globalThis.fetch, now = Date.now }) {
    this.clientID = clientID;
    this.clientSecret = clientSecret;
    this.fetch = fetch;
    this.now = now;
    this.cached = null;
    this.expiresAt = 0;
    // A cold isolate that gets several requests at once must not ask Spotify
    // several times: the first caller's promise is what everyone awaits.
    this.inFlight = null;
  }

  async token() {
    if (this.cached && this.now() < this.expiresAt) return this.cached;
    if (this.inFlight) return this.inFlight;

    this.inFlight = this.#fetchToken().finally(() => {
      this.inFlight = null;
    });
    return this.inFlight;
  }

  async #fetchToken() {
    const response = await this.fetch(TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "client_credentials",
        client_id: this.clientID,
        client_secret: this.clientSecret,
      }),
    });

    if (!response.ok) {
      throw new ProxyError(502, "spotify_token_rejected");
    }

    const payload = await response.json();
    if (!payload.access_token) throw new ProxyError(502, "spotify_token_missing");

    this.cached = payload.access_token;
    const lifetime = Number(payload.expires_in) || 3600;
    this.expiresAt = this.now() + Math.max(lifetime - EXPIRY_SKEW_SECONDS, 0) * 1000;
    return this.cached;
  }
}

export class ProxyError extends Error {
  /** @param {number} status @param {string} code */
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

/**
 * Answers GET /search?q=<query> with Spotify's own search body, unchanged --
 * the app keeps a single mapper that way.
 *
 * @param {Request} request
 * @param {{ tokens: TokenStore, fetch?: typeof globalThis.fetch }} deps
 */
export async function handleSearch(request, { tokens, fetch = globalThis.fetch }) {
  if (request.method !== "GET") {
    return jsonError(405, "method_not_allowed");
  }

  const url = new URL(request.url);
  if (url.pathname !== "/search") {
    return jsonError(404, "not_found");
  }

  const query = (url.searchParams.get("q") ?? "").trim();
  if (query === "") {
    // An empty search is not an error; it simply has no results. The client
    // never sends one, but a stray request should not cost a Spotify call.
    return jsonResponse({ tracks: { items: [] } });
  }
  if (query.length > MAX_QUERY_LENGTH) {
    return jsonError(414, "query_too_long");
  }

  let token;
  try {
    token = await tokens.token();
  } catch (error) {
    // The app must not be told to check its own credentials -- it has none.
    return jsonError(error instanceof ProxyError ? error.status : 502, "upstream_unavailable");
  }

  const search = new URL(SEARCH_URL);
  search.searchParams.set("q", query);
  search.searchParams.set("type", "track");
  search.searchParams.set("limit", String(SEARCH_LIMIT));

  let response;
  try {
    response = await fetch(search, {
      headers: { Authorization: `Bearer ${token}` },
    });
  } catch {
    // A transport failure must become an answer, not an exception out of the
    // Worker: an uncaught throw is served as Cloudflare's own HTML error page,
    // which the app cannot parse and which says more about our stack than the
    // caller needs to know. The thrown error itself is deliberately not read.
    return jsonError(502, "upstream_unavailable");
  }

  if (response.status === 429) {
    return jsonError(429, "rate_limited");
  }
  // A 401/403 here is the proxy's own credentials being refused, which is a
  // server problem however it looks from Spotify's side.
  if (response.status === 401 || response.status === 403) {
    return jsonError(502, "upstream_rejected_us");
  }
  if (!response.ok) {
    return jsonError(response.status, "upstream_error");
  }

  // A 200 that is not JSON is an upstream problem too -- an interception page,
  // a truncated body -- and `.json()` rejecting here would escape the Worker
  // exactly like a transport failure does.
  try {
    return jsonResponse(await response.json());
  } catch {
    return jsonError(502, "upstream_unavailable");
  }
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function jsonError(status, code) {
  return jsonResponse({ error: code }, status);
}
