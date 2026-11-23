import { validateBody, buildEvidence, shiftMonth, schema, instructions, renderAnswer, fallbackAnswer, questionIntent, explicitGoal, starterSuggestion } from './coach.mjs';

const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const reply = (status, data) => new Response(JSON.stringify(data), { status, headers });

async function readBody(request) {
  if (!request.body) throw Error('Missing body');
  const reader = request.body.getReader();
  const chunks = []; let length = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.length;
    if (length > 50000) { await reader.cancel(); throw Error('Too large'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder().decode(bytes));
}

export function createHandler(env, requestFetch = fetch, clock = () => new Date()) {
  return async request => {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    if (request.method !== 'POST') return reply(405, { error: 'method_not_allowed' });
    const authorization = request.headers.get('Authorization');
    if (!authorization?.startsWith('Bearer ')) return reply(401, { error: 'unauthorized' });
    const url = env('SUPABASE_URL'), anon = env('SUPABASE_ANON_KEY'), key = env('GROQ_API_KEY');
    if (!url || !anon || !key) return reply(503, { error: 'not_configured' });
    const authHeaders = { apikey: anon, Authorization: authorization, 'Content-Type': 'application/json' };
    try {
      const auth = await requestFetch(`${url}/auth/v1/user`, { headers: authHeaders, signal: AbortSignal.timeout(5000) });
      if (!auth.ok) return reply(401, { error: 'unauthorized' });
      const user = await auth.json();
      if (!user.id || user.is_anonymous) return reply(401, { error: 'unauthorized' });
      // Kuala Lumpur date; app's financial dates are stored as local calendar dates.
      const today = new Date(clock().getTime() + 8 * 3600000).toISOString().slice(0, 10);
      let input;
      try { input = validateBody(await readBody(request), today); }
      catch { return reply(400, { error: 'invalid_request' }); }
      // Reuse the existing atomic daily AI allowance: scans and chat share the limit.
      const quota = await requestFetch(`${url}/rest/v1/rpc/consume_receipt_scan`, {
        method: 'POST', headers: authHeaders, body: '{}', signal: AbortSignal.timeout(5000) });
      if (!quota.ok) return reply(503, { error: 'quota_unavailable' });
      if ((await quota.json()) !== true) return reply(429, { error: 'daily_limit_reached' });
      const filters = new URLSearchParams({ select: 'id,amount,type,category,category_id,date,is_recurring',
        user_id: `eq.${user.id}`, and: `(date.gte.${shiftMonth(input.month, -5)}-01,date.lt.${shiftMonth(input.month, 1)}-01)`, order: 'date.asc,id.asc' });
      const rows = [];
      // Explicit owner filter plus caller JWT RLS. Never use a service-role key.
      for (let offset = 0; offset < 10000; offset += 1000) {
        const response = await requestFetch(`${url}/rest/v1/transactions?${filters}&offset=${offset}&limit=1000`, {
          headers: authHeaders, signal: AbortSignal.timeout(8000) });
        if (!response.ok) throw Error('Data unavailable');
        const page = await response.json();
        if (!Array.isArray(page)) throw Error('Invalid data');
        rows.push(...page);
        if (page.length < 1000) break;
        if (offset === 9000) return reply(422, { error: 'too_many_records' });
      }
      const categoryQuery = new URLSearchParams({ select: 'id,name', user_id: `eq.${user.id}`, limit: '1000' });
      const categoryResponse = await requestFetch(`${url}/rest/v1/categories?${categoryQuery}`, { headers: authHeaders, signal: AbortSignal.timeout(5000) });
      if (!categoryResponse.ok) throw Error('Categories unavailable');
      const intent = questionIntent(input.message);
      const goal = intent === 'savings' ? explicitGoal(input.message, input.currency) : null;
      const matchingPlan = input.plan && (!goal || (input.plan.target === Math.round(goal.target * 100) && input.plan.months === goal.months));
      const scopedInput = { ...input, plan: intent === 'savings' && matchingPlan ? input.plan : null };
      const evidence = buildEvidence(rows, await categoryResponse.json(), scopedInput, today);
      if (goal && !scopedInput.plan) return reply(200, {
        answer: starterSuggestion(evidence, goal, input.currency), suggestPlan: true,
        goalHint: { target: goal.target, months: goal.months }, fallback: false,
        source: 'calculated', evidence, generatedAt: clock().toISOString(), currency: input.currency,
      });
      // Category rankings are exact ledger calculations; no language-model call is needed.
      if (intent === 'categories') return reply(200, {
        answer: fallbackAnswer(evidence, input.message), suggestPlan: false,
        goalHint: null, fallback: false, source: 'calculated', evidence,
        generatedAt: clock().toISOString(), currency: input.currency,
      });
      let result = { answer: fallbackAnswer(evidence, input.message), suggestPlan: intent === 'savings' && !scopedInput.plan, goalHint: null };
      let fallback = true;
      try {
        // Send aggregate evidence only: no merchant text, receipt notes, account IDs or user identity.
        const response = await requestFetch('https://api.groq.com/openai/v1/chat/completions', {
          method: 'POST', signal: AbortSignal.timeout(25000),
          headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ model: 'openai/gpt-oss-20b', reasoning_effort: 'low', max_completion_tokens: 2800,
            messages: [{ role: 'system', content: instructions },
              { role: 'user', content: JSON.stringify({ question: input.message, history: input.history, evidence }) }],
            response_format: { type: 'json_schema', json_schema: { name: 'spending_coach', strict: true, schema } } }),
        });
        if (response.ok) {
          const responseBody = await response.json();
          result = renderAnswer(JSON.parse(responseBody.choices?.[0]?.message?.content), evidence);
          fallback = false;
        } else {
          console.warn('coach_provider_http_status', response.status);
        }
      } catch {
        // Do not log exception text: it can include provider content or financial data.
        console.warn('coach_provider_or_validation_failed');
      }
      return reply(200, { ...result, fallback, evidence, generatedAt: clock().toISOString(), currency: input.currency });
    } catch {
      // Never log questions, financial data, tokens or provider response bodies.
      return reply(502, { error: 'coach_unavailable' });
    }
  };
}

