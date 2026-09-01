/**
 * Enrichissement narratif optionnel via LLM (OpenAI ou Anthropic).
 * Si aucune clé API n'est configurée, retourne null et le moteur à règles prend le relais.
 */

export async function enhanceNarration(
  systemPrompt: string,
  userPrompt: string,
): Promise<string | null> {
  const openaiKey = process.env.OPENAI_API_KEY?.trim();
  if (openaiKey) {
    return callOpenAI(openaiKey, systemPrompt, userPrompt);
  }
  const anthropicKey = process.env.ANTHROPIC_API_KEY?.trim();
  if (anthropicKey) {
    return callAnthropic(anthropicKey, systemPrompt, userPrompt);
  }
  return null;
}

async function callOpenAI(apiKey: string, system: string, user: string): Promise<string | null> {
  try {
    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: process.env.OPENAI_MODEL || "gpt-4o-mini",
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
        max_tokens: 600,
        temperature: 0.85,
      }),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
    return data.choices?.[0]?.message?.content?.trim() || null;
  } catch {
    return null;
  }
}

async function callAnthropic(apiKey: string, system: string, user: string): Promise<string | null> {
  try {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: process.env.ANTHROPIC_MODEL || "claude-sonnet-4-20250514",
        max_tokens: 600,
        system,
        messages: [{ role: "user", content: user }],
      }),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { content?: Array<{ type: string; text?: string }> };
    const block = data.content?.find((c) => c.type === "text");
    return block?.text?.trim() || null;
  } catch {
    return null;
  }
}
