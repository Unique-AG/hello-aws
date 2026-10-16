import { fileURLToPath } from 'node:url';

/** Absolute path to a fixture file under e2e/resources/. */
export function seedFile(name: string): string {
  return fileURLToPath(new URL(`../resources/${name}`, import.meta.url));
}
