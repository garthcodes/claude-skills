---
description: Answer a product question via /product-question, then boil the answer down to an ELI18 TLDR — one plain-English takeaway an 18-year-old would get instantly
argument-hint: [question about the product]
---

# Product Question TLDR

Answer this product question, then give the TLDR: "${1:the user's question}"

## How this works

This skill runs in two steps:

1. **Get the real answer.** Invoke the `product-question` skill (via the Skill tool) with the same question, and follow its instructions fully: answer exclusively from the code (never docs), verify behavior end-to-end, and produce its normal short, plain-language answer.
2. **Boil it down to an ELI18 TLDR.** Take that answer and compress it into a takeaway a smart 18-year-old with zero healthcare, billing, or software background would understand on first read.

## TLDR rules

- **One or two sentences, max.** If you need a third sentence, you haven't found the point yet.
- Everyday words only. No industry terms — no "eligibility check," "ERA," "claim adjudication," "ledger," "portal" — unless you translate them in place ("the insurance company's answer about what they'll pay").
- Use a relatable frame when it helps: "like getting a receipt," "like a subscription that retries your card."
- Keep it honest: the TLDR must not oversimplify into being wrong. If the full answer has one exception that changes the story, fold it in with a short "unless…" clause; otherwise drop edge cases entirely.
- If the code doesn't do the thing, the TLDR says so plainly: "The app doesn't do this."

## Output format

```
**Answer:** <the full /product-question answer, unchanged>

**TLDR (ELI18):** <the one-to-two-sentence plain-English takeaway>
```

## Example

**Q:** "What happens when a client misses a payment?"

**Answer:** "Nothing automatic happens on a missed payment itself — the invoice just stays unpaid. Each night the system retries charging any unpaid invoices against the client's saved card, and if a charge fails, the biller sees it flagged on the client's ledger. Clients are not notified of failed charges."

**TLDR (ELI18):** "It's like a subscription that quietly retries your card every night until it goes through — the client never hears about failed charges, but the billing staff sees them flagged."
