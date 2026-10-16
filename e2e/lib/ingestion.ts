import { config } from '../config';
import { gql, putBytes, pollUntil } from './http';

/**
 * Ingestion GraphQL flows (folder create, file upload, ingestion polling,
 * chunk read, cleanup). Query strings ported verbatim from the canonical suite.
 */
const URL = config.ingestionApiURL;

export async function createFolder(token: string, name: string): Promise<string> {
  const data = await gql(
    URL,
    token,
    `mutation CreateSubScope($name: String!, $parentId: String, $inheritAccess: Boolean) {
      createSubScope(name: $name, parentId: $parentId, inheritAccess: $inheritAccess) {
        id name parentId
      }
    }`,
    { name, parentId: null, inheritAccess: true },
  );
  return data.createSubScope.id as string;
}

const CONTENT_UPSERT = `mutation ContentUpsert($input: ContentCreateInput!, $fileUrl: String, $scopeId: String, $sourceOwnerType: String, $storeInternally: Boolean) {
  contentUpsert(input: $input, fileUrl: $fileUrl, scopeId: $scopeId, sourceOwnerType: $sourceOwnerType, storeInternally: $storeInternally) {
    id key byteSize mimeType writeUrl readUrl
  }
}`;

/** Three-step upload: reserve → PUT bytes to presigned URL → finalize. Returns contentId. */
export async function uploadFileToKB(
  token: string,
  scopeId: string,
  file: { key: string; mimeType: string; bytes: Buffer },
): Promise<string> {
  const first = await gql(URL, token, CONTENT_UPSERT, {
    input: { key: file.key, mimeType: file.mimeType, ownerType: 'SCOPE', byteSize: 0 },
    sourceOwnerType: 'USER',
    scopeId,
    storeInternally: true,
  });
  const { writeUrl, readUrl } = first.contentUpsert;

  await putBytes(writeUrl, file.bytes, file.mimeType);

  const second = await gql(URL, token, CONTENT_UPSERT, {
    input: { key: file.key, mimeType: file.mimeType, ownerType: 'SCOPE', byteSize: file.bytes.length },
    fileUrl: readUrl,
    sourceOwnerType: 'USER',
    scopeId,
    storeInternally: true,
  });
  return second.contentUpsert.id as string;
}

const CONTENT_BY_ID = `query ContentByIdWithMetadata($contentIds: [String!]!) {
  contentById(contentIds: $contentIds) {
    id mimeType ownerType key title byteSize ingestionState ingestionProgress metadata
  }
}`;

export async function contentById(token: string, contentId: string): Promise<any> {
  const data = await gql(URL, token, CONTENT_BY_ID, { contentIds: [contentId] });
  return data.contentById[0];
}

export async function waitForIngestionFinished(token: string, contentId: string, timeoutMs: number): Promise<any> {
  return pollUntil(
    async () => {
      const c = await contentById(token, contentId);
      // Fail fast on a terminal failure state instead of spinning to timeout.
      if (c && /FAIL|ERROR/i.test(String(c.ingestionState ?? ''))) {
        throw new Error(`Ingestion failed for ${contentId}: state=${c.ingestionState}`);
      }
      return c;
    },
    (c) => c?.ingestionState === 'FINISHED',
    { timeoutMs, label: `content ${contentId} ingestionState=FINISHED` },
  );
}

export async function getFirstChunk(token: string, contentId: string): Promise<any> {
  const data = await gql(
    URL,
    token,
    `query Chunk($contentId: String!, $skip: Int, $take: Int, $orderBy: [ChunkOrderByWithRelationInput!]) {
      chunk(contentId: $contentId, skip: $skip, take: $take, orderBy: $orderBy) {
        id contentId text startPage endPage
      }
    }`,
    { contentId, skip: 0, take: 1, orderBy: [{ createdAt: 'asc' }] },
  );
  return data.chunk[0];
}

export async function deleteScope(token: string, scopeId: string): Promise<void> {
  await gql(
    URL,
    token,
    `mutation DeleteScope($scopeId: String!) { deleteScope(scopeId: $scopeId) { id } }`,
    { scopeId },
  ).catch((e) => {
    console.warn(`deleteScope(${scopeId}) cleanup failed: ${e}`);
  });
}
