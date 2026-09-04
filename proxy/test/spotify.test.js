import { test } from "node:test";
import assert from "node:assert/strict";
import { TokenStore, handleSearch, SEARCH_LIMIT } from "../src/spotify.js";

/** A TokenStore that never calls out, for the tests that are not about tokens. */
function fixedTokens(token = "test-token") {
  return { token: async () => token };
}

function jsonOK(body) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

const spotifyBody = {
  tracks: { items: [{ id: "abc", name: "As It Was" }] },
};

test("a blank query answers with no results and never calls Spotify", async () => {
  const fetch = async () => {
    throw new Error("must not call Spotify for a blank query");
  };

  const response = await handleSearch(
    new Request("https://proxy.example.com/search?q=%20%20"),
    { tokens: fixedTokens(), fetch }
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { tracks: { items: [] } });
});

test("another path is not found", async () => {
  const response = await handleSearch(
    new Request("https://proxy.example.com/tracks?q=x"),
    { tokens: fixedTokens(), fetch: async () => jsonOK(spotifyBody) }
  );

  assert.equal(response.status, 404);
});

test("only GET is allowed", async () => {
  const response = await handleSearch(
    new Request("https://proxy.example.com/search?q=x", { method: "POST" }),
    { tokens: fixedTokens(), fetch: async () => jsonOK(spotifyBody) }
  );

  assert.equal(response.status, 405);
});

test("an absurdly long query is refused before it costs a Spotify call", async () => {
  const fetch = async () => {
    throw new Error("must not call Spotify");
  };

  const response = await handleSearch(
    new Request(`https://proxy.example.com/search?q=${"a".repeat(500)}`),
    { tokens: fixedTokens(), fetch }
  );

  assert.equal(response.status, 414);
});

test("passes Spotify's body through unchanged and asks for tracks only", async () => {
  let seen;
  const fetch = async (url, init) => {
    seen = { url: new URL(url), init };
    return jsonOK(spotifyBody);
  };

  const response = await handleSearch(
    new Request("https://proxy.example.com/search?q=as%20it%20was"),
    { tokens: fixedTokens("tok"), fetch }
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), spotifyBody);
  assert.equal(seen.url.searchParams.get("q"), "as it was");
  assert.equal(seen.url.searchParams.get("type"), "track");
  assert.equal(seen.url.searchParams.get("limit"), String(SEARCH_LIMIT));
  assert.equal(seen.init.headers.Authorization, "Bearer tok");
});

test("Spotify's rate limit is passed on as a rate limit", async () => {
  const response = await handleSearch(
    new Request("https://proxy.example.com/search?q=x"),
    { tokens: fixedTokens(), fetch: async () => new Response("", { status: 429 }) }
  );

  assert.equal(response.status, 429);
  assert.deepEqual(await response.json(), { error: "rate_limited" });
});

for (const status of [401, 403]) {
  test(`Spotify refusing our own credentials (${status}) is our problem, not the caller's`, async () => {
    const response = await handleSearch(
      new Request("https://proxy.example.com/search?q=x"),
      { tokens: fixedTokens(), fetch: async () => new Response("", { status }) }
    );

    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: "upstream_rejected_us" });
  });
}

test("a token that cannot be fetched answers 502, never leaking why", async () => {
  const tokens = {
    token: async () => {
      throw new Error("invalid_client");
    },
  };

  const response = await handleSearch(
    new Request("https://proxy.example.com/search?q=x"),
    { tokens, fetch: async () => jsonOK(spotifyBody) }
  );

  assert.equal(response.status, 502);
  const body = await response.json();
  assert.deepEqual(body, { error: "upstream_unavailable" });
  assert.ok(!JSON.stringify(body).includes("invalid_client"));
});

test("a warm isolate reuses its token instead of asking again", async () => {
  let calls = 0;
  const store = new TokenStore({
    clientID: "id",
    clientSecret: "secret",
    now: () => 0,
    fetch: async () => {
      calls += 1;
      return jsonOK({ access_token: "tok", expires_in: 3600 });
    },
  });

  assert.equal(await store.token(), "tok");
  assert.equal(await store.token(), "tok");
  assert.equal(calls, 1);
});

test("an expired token is fetched again", async () => {
  let calls = 0;
  let clock = 0;
  const store = new TokenStore({
    clientID: "id",
    clientSecret: "secret",
    now: () => clock,
    fetch: async () => {
      calls += 1;
      return jsonOK({ access_token: `tok-${calls}`, expires_in: 3600 });
    },
  });

  await store.token();
  clock = 3600 * 1000;
  assert.equal(await store.token(), "tok-2");
  assert.equal(calls, 2);
});

test("a cold isolate hit by several requests asks Spotify once", async () => {
  let calls = 0;
  const store = new TokenStore({
    clientID: "id",
    clientSecret: "secret",
    now: () => 0,
    fetch: async () => {
      calls += 1;
      await new Promise((resolve) => setTimeout(resolve, 5));
      return jsonOK({ access_token: "tok", expires_in: 3600 });
    },
  });

  const tokens = await Promise.all([store.token(), store.token(), store.token()]);

  assert.deepEqual(tokens, ["tok", "tok", "tok"]);
  assert.equal(calls, 1);
});

test("a rejected token request does not become a cached token", async () => {
  const store = new TokenStore({
    clientID: "id",
    clientSecret: "wrong",
    now: () => 0,
    fetch: async () => new Response("", { status: 400 }),
  });

  await assert.rejects(() => store.token());
  assert.equal(store.cached, null);
});

test("an upstream network failure answers 502 instead of throwing out of the Worker", async () => {
  const response = await handleSearch(
    new Request("https://proxy.example.com/search?q=x"),
    {
      tokens: fixedTokens(),
      fetch: async () => {
        throw new TypeError("connection reset by peer");
      },
    }
  );

  assert.equal(response.status, 502);
  const body = await response.json();
  assert.deepEqual(body, { error: "upstream_unavailable" });
  assert.ok(!JSON.stringify(body).includes("connection reset"));
});

test("a 200 that is not JSON answers 502 instead of throwing out of the Worker", async () => {
  const response = await handleSearch(
    new Request("https://proxy.example.com/search?q=x"),
    {
      tokens: fixedTokens(),
      fetch: async () =>
        new Response("<html>Cloudflare says no</html>", {
          status: 200,
          headers: { "Content-Type": "text/html" },
        }),
    }
  );

  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: "upstream_unavailable" });
});
