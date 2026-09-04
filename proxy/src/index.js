import { TokenStore, handleSearch } from "./spotify.js";

/**
 * Holds the Spotify client secret so the app does not have to. An IPA can be
 * unpacked; a Worker secret cannot.
 *
 * The endpoint is public on purpose: any key shipped in the app to guard it
 * would be just as extractable as the secret it replaced. What makes that
 * acceptable is how little it can do -- track search only, ten results, a
 * capped query length -- so the worst case is someone else's track search, not
 * the reuse of an account credential. Put Cloudflare's rate limiting in front
 * of it if that stops being enough.
 */

/** One store per isolate, so a warm isolate reuses its token. */
let tokens = null;

export default {
  async fetch(request, env) {
    if (!env.SPOTIFY_CLIENT_ID || !env.SPOTIFY_CLIENT_SECRET) {
      return new Response(JSON.stringify({ error: "not_configured" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    tokens ??= new TokenStore({
      clientID: env.SPOTIFY_CLIENT_ID,
      clientSecret: env.SPOTIFY_CLIENT_SECRET,
    });

    return handleSearch(request, { tokens });
  },
};
