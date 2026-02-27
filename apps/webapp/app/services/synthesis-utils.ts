/**
 * Calculate drift between current and previous persona
 * Returns a drift score (0-1) indicating how much the persona has changed
 * Uses token-level Jaccard distance for lexical comparison
 */
export async function calculatePersonaDrift(
  currentSummary: string,
  previousSummary: string,
): Promise<number> {
  if (!currentSummary && !previousSummary) return 0;
  if (!currentSummary || !previousSummary) return 1;

  const tokenize = (text: string): Set<string> =>
    new Set(
      text
        .toLowerCase()
        .replace(/[^\w\s]/g, "")
        .split(/\s+/)
        .filter(Boolean),
    );

  const currentTokens = tokenize(currentSummary);
  const previousTokens = tokenize(previousSummary);

  const intersection = new Set(
    [...currentTokens].filter((t) => previousTokens.has(t)),
  );
  const union = new Set([...currentTokens, ...previousTokens]);

  if (union.size === 0) return 0;

  // Jaccard distance = 1 - (intersection / union)
  return 1 - intersection.size / union.size;
}
