import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

/**
 * refresh-sentences — daily cron Edge Function
 * Finds vocabulary cards due today, generates new example sentences via Gemini,
 * updates the database, and logs cost to ai_usage.
 *
 * Triggered by pg_cron via pg_net at 23:00 UTC (= 7:00 AM Taiwan time).
 * Uses service_role key (set as SUPABASE_SERVICE_ROLE_KEY secret).
 */

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SB_SERVICE_ROLE_KEY")!;
const GOOGLE_KEY = Deno.env.get("GOOGLE_API_KEY")!;
const GEMINI_MODEL = "gemini-3.1-flash-lite";

// Taiwan time "today" string (YYYY-MM-DD)
function todayTW(): string {
  return new Date().toLocaleDateString("sv-SE", { timeZone: "Asia/Taipei" });
}

async function sbQuery(path: string, opts: RequestInit = {}) {
  const url = `${SUPABASE_URL}/rest/v1/${path}`;
  const sep = path.includes("?") ? "&" : "?";
  const res = await fetch(`${url}${sep}apikey=${SERVICE_ROLE_KEY}`, {
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      Prefer: "return=representation",
      ...(opts.headers as Record<string, string> || {}),
    },
    ...opts,
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Supabase ${res.status}: ${t.slice(0, 300)}`);
  }
  const text = await res.text();
  return text ? JSON.parse(text) : [];
}

async function generateSentence(word: string): Promise<{ context: string; context_zh: string }> {
  const prompt = `Generate ONE natural English example sentence using the word "${word}". The sentence should be 10-20 words, suitable for a high school student (B1-B2 level). Then translate the sentence to Traditional Chinese.

Return ONLY this exact format (no other text):
EN: <sentence>
ZH: <translation>`;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GOOGLE_KEY}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { maxOutputTokens: 128 },
    }),
  });

  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Gemini ${res.status}: ${t.slice(0, 200)}`);
  }

  const json = await res.json();
  const text = json.candidates?.[0]?.content?.parts?.[0]?.text || "";
  const usage = json.usageMetadata || {};

  const enMatch = text.match(/EN:\s*(.+)/);
  const zhMatch = text.match(/ZH:\s*(.+)/);

  const inputTokens = usage.promptTokenCount || 0;
  const outputTokens = usage.candidatesTokenCount || 0;
  // flash-lite pricing: $0.25/MTok in, $1.5/MTok out (approximate)
  const costUsd = (inputTokens * 0.25 + outputTokens * 1.5) / 1e6;

  return {
    context: enMatch ? enMatch[1].trim() : "",
    context_zh: zhMatch ? zhMatch[1].trim() : "",
    _costUsd: costUsd,
    _inputTokens: inputTokens,
    _outputTokens: outputTokens,
  } as any;
}

serve(async (req) => {
  // Allow manual trigger via POST and cron via POST/GET
  const t = todayTW();
  console.log(`[refresh-sentences] Starting for date: ${t}`);

  try {
    // Find all enabled decks (refresh_sentences=true or null, not deleted)
    const enabledDecks = await sbQuery(
      `decks?deleted_at=is.null&refresh_sentences=neq.false&select=id`
    );
    const enabledDeckIds: string[] = enabledDecks.map((d: any) => d.id);

    // Get card IDs in enabled decks (chunked to avoid URL limit)
    const eligibleIds = new Set<string>();
    const DCHUNK = 100;
    for (let i = 0; i < enabledDeckIds.length; i += DCHUNK) {
      const ids = enabledDeckIds.slice(i, i + DCHUNK);
      const rows = await sbQuery(`card_decks?deck_id=in.(${ids.join(",")})&select=card_id`);
      rows.forEach((r: any) => eligibleIds.add(r.card_id));
    }

    // Find all non-mastered vocabulary due today that has been reviewed at least once
    const allDue = await sbQuery(
      `vocabulary?next_review=eq.${t}&mastered=eq.false&select=id,word,student_id,context&sm_reps=gt.0`
    );
    // Keep only cards that are in at least one enabled deck
    const vocab = eligibleIds.size > 0
      ? allDue.filter((v: any) => eligibleIds.has(v.id))
      : [];

    if (!vocab.length) {
      console.log("[refresh-sentences] No eligible cards due today.");
      return new Response(JSON.stringify({ date: t, refreshed: 0, cost_usd: 0 }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log(`[refresh-sentences] Found ${vocab.length} cards to refresh.`);

    let refreshed = 0;
    let totalCost = 0;
    const errors: string[] = [];

    // Process in batches of 10 (concurrent)
    const BATCH = 10;
    for (let i = 0; i < vocab.length; i += BATCH) {
      const batch = vocab.slice(i, i + BATCH);
      const results = await Promise.allSettled(
        batch.map(async (v: any) => {
          const result = await generateSentence(v.word);
          if (!result.context) {
            throw new Error(`Empty sentence for "${v.word}"`);
          }
          // Update vocabulary
          await sbQuery(`vocabulary?id=eq.${v.id}`, {
            method: "PATCH",
            body: JSON.stringify({
              context: result.context,
              context_zh: result.context_zh,
            }),
          });
          return { student_id: v.student_id, cost: (result as any)._costUsd || 0 };
        })
      );

      for (const r of results) {
        if (r.status === "fulfilled") {
          refreshed++;
          totalCost += r.value.cost;
        } else {
          errors.push(r.reason?.message || "unknown error");
        }
      }
    }

    // Log cost to ai_usage (group by student)
    const studentCosts: Record<string, number> = {};
    // Re-calculate per student from vocab
    for (const v of vocab) {
      const perCard = totalCost / Math.max(refreshed, 1);
      studentCosts[v.student_id] = (studentCosts[v.student_id] || 0) + perCard;
    }
    for (const [sid, cost] of Object.entries(studentCosts)) {
      if (cost > 0) {
        await sbQuery("ai_usage", {
          method: "POST",
          body: JSON.stringify({
            student_id: sid,
            cost_usd: cost,
            action: "refresh_sentences",
          }),
        }).catch((e: Error) => console.error(`[ai_usage] ${e.message}`));
      }
    }

    // Log summary to app_config for teacher dashboard
    await sbQuery("app_config?key=eq.last_sentence_refresh", { method: "DELETE" }).catch(() => {});
    await sbQuery("app_config", {
      method: "POST",
      body: JSON.stringify({
        key: "last_sentence_refresh",
        value: JSON.stringify({
          date: t,
          refreshed,
          errors: errors.length,
          cost_usd: totalCost,
          timestamp: new Date().toISOString(),
        }),
      }),
    }).catch((e: Error) => console.error(`[app_config] ${e.message}`));

    const summary = { date: t, refreshed, errors: errors.length, cost_usd: totalCost };
    console.log(`[refresh-sentences] Done:`, summary);

    return new Response(JSON.stringify(summary), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("[refresh-sentences] Fatal:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
