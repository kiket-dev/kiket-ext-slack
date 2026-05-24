import { normalizeSlackRawEvent } from './normalize.js';
import { toAdapterContext, type ExtensionRawEventInput } from './adapter-context.js';

export type { ExtensionRawEventInput } from './adapter-context.js';

export function normalizeExtensionRawEvent(raw: ExtensionRawEventInput) {
  return normalizeSlackRawEvent(toAdapterContext(raw));
}
