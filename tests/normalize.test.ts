import { describe, expect, it } from 'vitest';
import { normalizeSlackRawEvent } from '../src/index.js';

const CASE_ID = '11111111-1111-4111-8111-111111111111';

describe('normalizeSlackRawEvent', () => {
  it('normalizes approval messages', () => {
    const normalized = normalizeSlackRawEvent({
      organizationId: 'org-1',
      rawEventId: 'raw-1',
      idempotencyKey: 'slack:msg:1',
      sourceEventType: 'event_callback',
      receivedAt: new Date('2026-04-25T10:00:00.000Z'),
      payload: {
        type: 'event_callback',
        event: {
          type: 'message',
          channel: 'C123',
          ts: '1714032000.000100',
          user: 'U123',
          text: `Approved for deploy — case: ${CASE_ID}`,
        },
      },
    });

    expect(normalized.eventType).toBe('approval.recorded');
    expect(normalized.attributes.approved).toBe(true);
    expect(normalized.evidence[0]?.evidenceType).toBe('slack_approval');
  });

  it('normalizes non-approval messages as observed evidence', () => {
    const normalized = normalizeSlackRawEvent({
      organizationId: 'org-1',
      rawEventId: 'raw-2',
      idempotencyKey: 'slack:msg:2',
      sourceEventType: 'event_callback',
      receivedAt: new Date('2026-04-25T10:00:00.000Z'),
      payload: {
        event: {
          type: 'message',
          channel: 'C123',
          ts: '1714032001.000100',
          text: `Update on rollout caseId: ${CASE_ID}`,
        },
      },
    });

    expect(normalized.eventType).toBe('evidence.observed');
    expect(normalized.evidence[0]?.evidenceType).toBe('slack_message');
  });
});
