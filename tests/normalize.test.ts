import { describe, expect, it } from 'vitest';
import { normalizeSlackRawEvent } from '../src/normalize.js';

const CASE_ID = '11111111-1111-4111-8111-111111111111';
const receivedAt = new Date('2026-05-22T10:00:01.000Z');

function baseContext(overrides: Partial<Parameters<typeof normalizeSlackRawEvent>[0]> = {}) {
  return {
    organizationId: 'org-1',
    workspaceId: 'ws-1',
    processId: 'proc-1',
    rawEventId: 'raw-1',
    idempotencyKey: 'idem-1',
    sourceEventType: 'event_callback',
    receivedAt,
    payload: {},
    metadata: { deliveryId: 'delivery-1' },
    ...overrides,
  };
}

describe('normalizeSlackRawEvent', () => {
  it('normalizes approval messages', () => {
    const normalized = normalizeSlackRawEvent(
      baseContext({
        payload: {
          event: {
            type: 'message',
            channel: 'C123',
            ts: '1716375600.000100',
            text: `Approved for release. case: ${CASE_ID}`,
            user: 'U123',
          },
        },
      }),
    );

    expect(normalized.eventType).toBe('approval.recorded');
    expect(normalized.caseId).toBe(CASE_ID);
    expect(normalized.evidence[0]?.evidenceType).toBe('slack_approval');
  });

  it('normalizes non-approval messages as evidence', () => {
    const normalized = normalizeSlackRawEvent(
      baseContext({
        payload: {
          event: {
            type: 'message',
            channel: 'C123',
            ts: '1716375601.000100',
            text: `FYI case: ${CASE_ID}`,
            user: 'U123',
          },
        },
      }),
    );

    expect(normalized.eventType).toBe('evidence.observed');
    expect(normalized.caseId).toBe(CASE_ID);
    expect(normalized.evidence[0]?.evidenceType).toBe('slack_message');
  });
});
