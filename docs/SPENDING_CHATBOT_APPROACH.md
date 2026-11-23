# Spendly spending coach: proposed approach

The first-stage chatbot is implemented and its cloud endpoint is deployed following explicit approval for Groq processing. Live market comparisons and persistent saved goals remain later stages. See SPENDING_COACH_IMPLEMENTATION.md for behavior and verification details.

## Recommended first version

Use a chat screen connected to the existing authenticated backend and AI provider. Do not train a new model. Let ordinary application code calculate amounts and let the language model explain the result and ask follow-up questions.

Start with read-only questions: where money went, month-to-month changes, recurring expenses, and a savings goal with an explicit deadline. All totals must come from the user's own recorded transactions. Use three to six completed months when available; identify partial months and incomplete records explicitly. Keep salary separate from refunds, gifts, and irregular income when estimating future income.

The current app loads one selected month for display. The coach will need its own authenticated historical query; it must not assume the displayed month contains the full history. Account opening balances are not income. Transfers, debt principal, credit-card repayments, and refunds need explicit classification to avoid counting them as fresh spending or earnings twice.

## How a question becomes an answer

1. Resolve the signed-in user from the verified session. Never accept a user ID chosen by the model as authorization.
2. Parse the question into a small allowlisted operation: spending summary, category trend, recurring commitments, savings feasibility, or current public information.
3. Execute bounded, parameter-validated data functions; no free-form SQL or unrestricted account access. Aggregate money in integer minor units to avoid rounding drift.
4. Return an evidence object containing the period, income, expenses, disposable surplus, categories, record count, freshness, and assumptions.
5. Generate a short explanation with the numbers, specific choices, and an indication of missing information. Validate numeric claims against the evidence object before showing the answer.
6. Show proposed budgets or goals as previews. Require the user to choose Save before changing their records.

Suggested backend tools: get_monthly_cash_flow, compare_categories, get_recurring_commitments, calculate_savings_plan, find_public_price_information. Groq supports application-controlled function calling: https://console.groq.com/docs/tool-use/local-tool-calling

## Example: RM500 within two months

Ask for an exact deadline and whether existing savings count. If the user starts at zero and has two full months, the target is RM250 per month. First check whether the current expected surplus already covers this. Only then calculate any extra reductions required.

Ask for expected take-home income, unavoidable bills, debt commitments, and irregular upcoming expenses when these cannot be established from the records. Propose category reductions capped by actual discretionary spending, with a buffer. Explain an infeasible target honestly and offer a longer deadline. Do not invent a RM100 food reduction if recorded discretionary food spending is only RM60.

An example response could show: target, time remaining, current expected surplus, remaining monthly gap, and two or three user-selectable changes. Any illustrative amount must be labelled as an example until calculated from the user's data.

## Current market information

Add this after the personal-data calculations are reliable. Query public sources using the item, approximate area, and requested comparison; never send bank balances, private transaction descriptions, or conversation history as search terms. Show the source URL, observation date, location, unit/pack size, and expiry or conditions where available.

For Malaysian grocery comparisons, evaluate the official PriceCatcher dataset and its premise/item lookup tables: https://data.gov.my/data-catalogue/pricecatcher . It contains observed prices, not a guarantee of stock or today's checkout price. Match units and location and consider travel cost before claiming a saving.

Official retailer offers, bank product pages, and government information can complement this. If no current source is available, say it cannot be verified. Treat retrieved webpages as untrusted data, not instructions. Search on demand and cache public results with freshness limits; do not search for every private-data question. Groq also documents built-in search on supported models, but model support and cost should be verified before selection: https://console.groq.com/docs/tool-use/built-in-tools/browser-search

## Main challenges and controls

| Challenge | Practical control |
| --- | --- |
| Missing or inaccurate receipt/income data | Ask targeted questions, allow corrections, label coverage and uncertainty. |
| Incorrect arithmetic or invented advice | Deterministic calculations, evidence-backed answers, tests for all numeric claims. |
| Irregular salary and partial months | Separate recurring income and one-offs; compare equal periods or completed months. |
| Private financial information | Per-user authorization, minimum necessary AI context, no secrets or raw finance data in public searches; clear chat retention/deletion settings. |
| Stale promotions or non-comparable prices | Date, source, location, unit size, eligibility, and expiry checks. |
| Unrealistic savings plans | Protect essentials and debt commitments; user-controlled assumptions and a buffer. |
| Cost and latency | Bounded tool calls, summaries instead of entire ledgers, request quotas, timeouts and cached public information. |
| Model/provider changes | Configurable provider/model and repeatable evaluation cases. |

## Delivery stages

1. Personal spending Q&A and savings calculations, with explicit income/commitment inputs and read-only access.
2. User-approved goals and budgets, progress tracking, and explanation of missed targets.
3. Source-backed Malaysian price/offer comparisons and optional reminders.

The first stage is a moderate feature. Reliable market comparisons are the larger ongoing workload because they need source maintenance and freshness checks. Cloud execution keeps the phone workload small, but AI/search use adds a recurring service cost. Measure actual usage in a pilot before setting a subscription price or promising an operating budget.

Acceptance checks should cover cross-user access, empty history, no income, negative cash flow, partial months, month/year boundaries, irregular income, an impossible goal, malicious receipt/search content, stale sources, service outages, and deletion/sign-out behavior.
