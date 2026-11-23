import { instructions, schema, readResponse } from './receipt.mjs';

const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const reply = (status, error) => new Response(JSON.stringify({ error }), { status, headers });

async function readBody(request) {
  if (!request.body) throw new Error('Missing body');
  const reader = request.body.getReader();
  const chunks = [];
  let bytes = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > 64000) { await reader.cancel(); throw new Error('Too large'); }
    chunks.push(value);
  }
  const merged = new Uint8Array(bytes);
  let offset = 0;
  for (const chunk of chunks) { merged.set(chunk, offset); offset += chunk.length; }
  const body = JSON.parse(new TextDecoder().decode(merged));
  if (typeof body.text !== 'string' || !body.text.trim() || body.text.length > 20000) {
    throw new Error('Invalid text');
  }
  return body.text;
}

export function createHandler(env, requestFetch = fetch) {
  return async (request) => {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    if (request.method !== 'POST') return reply(405, 'method_not_allowed');
    const authorization = request.headers.get('Authorization');
    if (!authorization?.startsWith('Bearer ')) return reply(401, 'unauthorized');
    const url = env('SUPABASE_URL');
    const anon = env('SUPABASE_ANON_KEY');
    const key = env('GROQ_API_KEY');
    if (!url || !anon || !key) return reply(503, 'not_configured');
    const authHeaders = { apikey: anon, Authorization: authorization, 'Content-Type': 'application/json' };
    try {
      const auth = await requestFetch(`${url}/auth/v1/user`, {
        headers: authHeaders, signal: AbortSignal.timeout(5000),
      });
      if (!auth.ok || !(await auth.json()).id) return reply(401, 'unauthorized');
      let text;
      try { text = await readBody(request); } catch { return reply(400, 'invalid_receipt_text'); }
      // Atomic database quota, shared across all function instances. Fail closed.
      const quota = await requestFetch(`${url}/rest/v1/rpc/consume_receipt_scan`, {
        method: 'POST', headers: authHeaders, body: '{}', signal: AbortSignal.timeout(5000),
      });
      if (!quota.ok) return reply(503, 'quota_unavailable');
      if ((await quota.json()) !== true) return reply(429, 'daily_limit_reached');
      // Only Groq is called. Errors return to the local parser, never another provider.
      // The key owner's Groq account must remain on the Free plan for free usage.
      const response = await requestFetch('https://api.groq.com/openai/v1/chat/completions', {
        method: 'POST', signal: AbortSignal.timeout(25000),
        headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ model: 'openai/gpt-oss-20b',
          messages: [{ role: 'system', content: instructions }, { role: 'user', content: text }],
          reasoning_effort: 'low',
          max_completion_tokens: 4000,
          response_format: { type: 'json_schema', json_schema: { name: 'receipt', strict: true, schema } },
        }),
      });
      if (response.status === 429) return reply(429, 'provider_limit_reached');
      if (!response.ok) return reply(502, 'ai_unavailable');
      const receipt = readResponse(await response.json());
      return new Response(JSON.stringify(receipt), { status: 200, headers });
    } catch {
      // Do not expose or log receipt text, API keys, or upstream response bodies.
      return reply(502, 'extraction_failed');
    }
  };
}
