import { config } from '../config';

const API_VERSION = '2023-12-06';

/**
 * The public SDK's search endpoint. `searchType` picks the index, so a caller
 * can tell the full-text store and the vector store apart instead of asking
 * for COMBINED and learning only that "search" broke.
 */
export type SearchType = 'COMBINED' | 'FULL_TEXT' | 'POSTGRES_FULL_TEXT' | 'VECTOR';

export type SearchHit = {
  id: string;
  chunkId: string;
  text: string;
  key: string;
  title: string | null;
};

export type PublicApiCaller = {
  userId: string;
  companyId: string;
  appId: string;
  apiKey: string;
};

/** POST /search/search. Returns the status alongside the hits so a 500 is assertable. */
export async function search(
  caller: PublicApiCaller,
  body: { searchString: string; searchType: SearchType; scopeIds?: string[]; limit?: number },
): Promise<{ status: number; hits: SearchHit[]; raw: string }> {
  const res = await fetch(`${config.publicSdkURL}/search/search`, {
    method: 'POST',
    headers: {
      Accept: '*/*',
      'Content-Type': 'application/json',
      'x-api-version': API_VERSION,
      'x-company-id': caller.companyId,
      'x-user-id': caller.userId,
      'x-app-id': caller.appId,
      Authorization: `Bearer ${caller.apiKey}`,
    },
    body: JSON.stringify({ limit: 20, ...body }),
  });
  const raw = await res.text();
  let hits: SearchHit[] = [];
  try {
    const json = JSON.parse(raw);
    hits = (Array.isArray(json) ? json : (json.data ?? json.results ?? [])) as SearchHit[];
  } catch {
    // Left empty on purpose: the status and raw body are what a failure needs.
  }
  return { status: res.status, hits, raw };
}
