/** Extract @username mentions from a text string. Returns lowercased unique usernames. */
export function extractMentions(text: string): string[] {
  if (!text) return [];
  const matches = text.matchAll(/(^|\s)@([a-z0-9_.]{3,32})/gi);
  const out = new Set<string>();
  for (const m of matches) {
    if (m[2]) out.add(m[2].toLowerCase());
  }
  return [...out];
}