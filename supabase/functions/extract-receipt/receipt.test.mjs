import test from 'node:test';
import assert from 'node:assert/strict';
import { validateReceipt, readResponse } from './receipt.mjs';
import { createHandler } from './handler.mjs';

const receipt = () => ({ merchant: 'Shop', receipt_number: null, currency: 'MYR',
  date: '2026-10-09', time: null, total: 15, payment_method: null, category: 'groceries',
  items: [{ name: 'Milk', quantity: 2, unit_price: 7.5, amount: 15 }], review_reasons: [] });
const response = (value) => ({ choices: [{ finish_reason: 'stop',
  message: { role: 'assistant', content: JSON.stringify(value) } }] });
const json = (value, status = 200) => new Response(JSON.stringify(value), { status });
const env = (name) => ({ SUPABASE_URL: 'https://example.supabase.co', SUPABASE_ANON_KEY: 'public',
  GROQ_API_KEY: 'test-only' })[name];
const request = (text = 'Shop\nTOTAL 15.00', authenticated = true) => new Request('https://example.test', {
  method: 'POST', headers: authenticated ? { Authorization: 'Bearer test-token' } : {}, body: JSON.stringify({ text }),
});

test('valid receipt preserves missing time and duplicate purchases', () => {
  const r = receipt(); r.items.push({ ...r.items[0] }); r.total = 30;
  const result = readResponse(response(r));
  assert.equal(result.items.length, 2);
  assert.equal(result.time, null);
  assert.deepEqual(result.review_reasons, []);
});

test('Ninso structured result preserves household category and payment metadata', () => {
  const result = readResponse(response({ ...receipt(), merchant: 'Ninso',
    receipt_number: 'S2LB98202609290073', date: '2026-09-29', total: 2.8,
    category: 'homeAppliances', payment_method: 'Debit card / bank',
    items: [{ name: 'Ninso Wet Tissue', quantity: 1, unit_price: 2.8, amount: 2.8 }] }));
  assert.equal(result.category, 'homeAppliances');
  assert.equal(result.receipt_number, 'S2LB98202609290073');
  assert.equal(result.payment_method, 'Debit card / bank');
  assert.deepEqual(result.review_reasons, []);
});
test('rejects invalid dates, categories, negative totals and unexpected fields', () => {
  for (const changes of [{ date: '2026-02-31' }, { category: 'salary' }, { total: -1 }, { injected: true }]) {
    assert.throws(() => validateReceipt({ ...receipt(), ...changes }));
  }
});
test('flags arithmetic mismatch without rewriting printed total', () => {
  const result = validateReceipt({ ...receipt(), total: 16 });
  assert.equal(result.total, 16);
  assert.match(result.review_reasons.join(' '), /Item totals differ/);
});
test('incomplete and refused model responses are rejected', () => {
  for (const finish_reason of ['length', 'content_filter', 'tool_calls', null]) {
    assert.throws(() => readResponse({ choices: [{ finish_reason, message: { content: JSON.stringify(receipt()) } }] }));
  }
  assert.throws(() => readResponse({ choices: [{ finish_reason: 'stop', message: { refusal: 'Refused', content: JSON.stringify(receipt()) } }] }));
  for (const body of [null, {}, { choices: [] }, { choices: [{ finish_reason: 'stop', message: { content: null } }] }]) {
    assert.throws(() => readResponse(body));
  }
});
test('unauthenticated requests never call upstream services', async () => {
  const handler = createHandler(env, () => { throw new Error('Should not be called'); });
  assert.equal((await handler(request('text', false))).status, 401);
});
test('invalid JWT never reaches quota or Groq', async () => {
  let calls = 0;
  const handler = createHandler(env, async () => { calls++; return json({}, 401); });
  assert.equal((await handler(request())).status, 401);
  assert.equal(calls, 1);
});
test('oversized input is rejected before quota or provider calls', async () => {
  let calls = 0;
  const handler = createHandler(env, async () => { calls++; return json({ id: 'user' }); });
  assert.equal((await handler(request('x'.repeat(65000)))).status, 400);
  assert.equal(calls, 1);
});
test('quota exhaustion and quota failure block Groq calls', async () => {
  for (const status of [200, 500]) {
    let calls = 0;
    const handler = createHandler(env, async () => ++calls === 1 ? json({ id: 'user' }) : json(false, status));
    assert.equal((await handler(request())).status, status === 200 ? 429 : 503);
    assert.equal(calls, 2);
  }
});
test('authenticated extraction calls only Groq using its structured-output contract', async () => {
  let calls = 0;
  const handler = createHandler(env, async (url, init) => {
    calls++;
    if (calls === 1) return json({ id: 'user' });
    if (calls === 2) return json(true);
    assert.equal(url, 'https://api.groq.com/openai/v1/chat/completions');
    assert.equal(init.headers.Authorization, 'Bearer test-only');
    const body = JSON.parse(init.body);
    assert.equal(body.model, 'openai/gpt-oss-20b');
    assert.equal(body.response_format.json_schema.strict, true);
    assert.equal(body.response_format.type, 'json_schema');
    assert.equal(body.messages[0].role, 'system');
    assert.equal(body.messages[1].content, 'Shop\nTOTAL 15.00');
    assert.equal(body.max_completion_tokens, 4000);
    assert.equal(body.reasoning_effort, 'low');
    assert.equal('max_output_tokens' in body, false);
    return json(response(receipt()));
  });
  const result = await handler(request());
  assert.equal(result.status, 200);
  assert.equal((await result.json()).total, 15);
});
test('provider failures return generic errors without upstream details', async () => {
  let calls = 0;
  const handler = createHandler(env, async () => {
    calls++;
    if (calls === 1) return json({ id: 'user' });
    if (calls === 2) return json(true);
    return json({ secret: 'private upstream error' }, 500);
  });
  const result = await handler(request());
  assert.equal(result.status, 502);
  assert.equal(await result.text(), '{"error":"ai_unavailable"}');
  assert.equal(calls, 3);
});

test('Groq rate limit is returned without retries or paid fallback', async () => {
  let calls = 0;
  const handler = createHandler(env, async (url) => {
    calls++;
    if (calls === 1) return json({ id: 'user' });
    if (calls === 2) return json(true);
    assert.equal(new URL(url).hostname, 'api.groq.com');
    return json({ error: 'rate limit' }, 429);
  });
  const result = await handler(request());
  assert.equal(result.status, 429);
  assert.equal((await result.json()).error, 'provider_limit_reached');
  assert.equal(calls, 3);
});

test('an old OpenAI key cannot activate extraction without a Groq key', async () => {
  const legacyEnv = (name) => name === 'GROQ_API_KEY' ? undefined : name === 'OPENAI_API_KEY' ? 'legacy-key' : env(name);
  const handler = createHandler(legacyEnv, () => { throw new Error('Must not call any provider'); });
  const result = await handler(request());
  assert.equal(result.status, 503);
  assert.equal((await result.json()).error, 'not_configured');
});
