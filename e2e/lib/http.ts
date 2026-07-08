/**
 * Tiny fetch-based HTTP/GraphQL helpers. No client library — matches how the
 * canonical suite talks to the gateway (raw fetch + hand-written queries).
 */

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function postForm(
  url: string,
  body: Record<string, string>,
  headers: Record<string, string> = {},
): Promise<any> {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...headers },
    body: new URLSearchParams(body).toString(),
  });
  if (!res.ok) {
    throw new Error(`POST ${url} failed: ${res.status} ${await res.text()}`);
  }
  return res.json();
}

/**
 * Execute a GraphQL operation. Retries transient failures with backoff.
 * Throws on HTTP error or a non-empty `errors` array so tests fail loudly.
 */
export async function gql<T = any>(
  url: string,
  token: string,
  query: string,
  variables: Record<string, unknown> = {},
  { retries = 3 }: { retries?: number } = {},
): Promise<T> {
  let lastErr: unknown;
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: '*/*',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ query, variables }),
      });
      if (!res.ok) throw new Error(`GraphQL ${url} HTTP ${res.status}: ${await res.text()}`);
      const json = await res.json();
      if (json.errors?.length) {
        throw new Error(`GraphQL ${url} errors: ${JSON.stringify(json.errors)}`);
      }
      return json.data as T;
    } catch (err) {
      lastErr = err;
      if (attempt < retries) await sleep(1000 * 2 ** attempt);
    }
  }
  throw lastErr;
}

export async function putBytes(url: string, bytes: Buffer, mimeType: string): Promise<void> {
  // Presigned upload URL: send only Content-Type (S3 presigned URLs reject an
  // extra Authorization header; the Azure-specific x-ms-blob-type isn't needed).
  const res = await fetch(url, {
    method: 'PUT',
    headers: { 'Content-Type': mimeType },
    body: bytes as any,
  });
  if (!res.ok) throw new Error(`PUT ${url} failed: ${res.status} ${await res.text()}`);
}

/** Poll `fn` until `pred` is true or timeout. Returns the last value. */
export async function pollUntil<T>(
  fn: () => Promise<T>,
  pred: (v: T) => boolean,
  { timeoutMs, intervalMs = 1000, label = 'condition' }: { timeoutMs: number; intervalMs?: number; label?: string },
): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  let last: T;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    last = await fn();
    if (pred(last)) return last;
    if (Date.now() > deadline) {
      throw new Error(`Timed out after ${timeoutMs}ms waiting for ${label}. Last value: ${JSON.stringify(last)}`);
    }
    await sleep(intervalMs);
  }
}
