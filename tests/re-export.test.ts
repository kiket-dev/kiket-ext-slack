import { describe, expect, it } from 'vitest';
import { normalizeSlackRawEvent, SLACK_ADAPTER_SOURCE_EVENT_TYPES } from '../src/index.js';

describe('slack extension entry', () => {
  it('re-exports slack-adapter normalizers', () => {
    expect(SLACK_ADAPTER_SOURCE_EVENT_TYPES).toContain('message');
    expect(typeof normalizeSlackRawEvent).toBe('function');
  });
});
