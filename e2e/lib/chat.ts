import { config } from '../config';
import { gql } from './http';

/**
 * Delete a Space V2 / assistant. Best-effort cleanup — logs on failure rather
 * than throwing, so a teardown regression is visible without failing the test.
 */
export async function deleteAssistant(token: string, assistantId: string): Promise<void> {
  await gql(
    config.chatApiURL,
    token,
    `mutation DeleteAssistant($id: String!) { deleteAssistant(id: $id) { id } }`,
    { id: assistantId },
  ).catch((e) => {
    console.warn(`deleteAssistant(${assistantId}) cleanup failed: ${e}`);
  });
}
