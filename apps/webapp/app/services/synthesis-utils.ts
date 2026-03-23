/**
 * Calculate drift between current and previous persona
 * Returns a drift score (0-1) indicating how much the persona has changed.
 * Uses Jaccard similarity on word tokens: drift = 1 - |A ∩ B| / |A ∪ B|
 */
export async function calculatePersonaDrift(
  currentSummary: string,
  previousSummary: string,
): Promise<number> {
  const tokenize = (s: string): Set<string> =>
    new Set((s.toLowerCase().match(/\b\w+\b/g) ?? []) as string[]);

  const a = tokenize(currentSummary);
  const b = tokenize(previousSummary);

  if (a.size === 0 && b.size === 0) return 0;

  const intersection = [...a].filter((token) => b.has(token)).length;
  const union = new Set([...a, ...b]).size;

  return 1 - intersection / union;
}
