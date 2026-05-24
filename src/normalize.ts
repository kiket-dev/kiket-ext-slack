export interface SlackRawEventContext {
  organizationId: string;
  workspaceId?: string | null;
  processId?: string | null;
  rawEventId: string;
  idempotencyKey: string;
  sourceEventType: string;
  receivedAt: Date;
  payload: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}

export interface NormalizedOperationalEventOutput {
  organizationId: string;
  workspaceId?: string;
  processId?: string;
  caseId?: string;
  eventType: string;
  sourceSystem: 'slack';
  sourceObjectId?: string;
  actor: Record<string, unknown>;
  subject: Record<string, unknown>;
  occurredAt: Date;
  correlationIds: string[];
  attributes: Record<string, unknown>;
  dedupeKey: string;
  evidence: Array<{
    evidenceType: string;
    title: string;
    sourceObjectId?: string;
    capturedAt: Date;
    payload: Record<string, unknown>;
    dedupeKey: string;
  }>;
  intents: Array<{
    type: string;
    targetType?: string;
    targetId?: string;
    reason: string;
    attributes: Record<string, unknown>;
    idempotencyKey: string;
  }>;
}

const CASE_ID_PATTERN =
  /(?:kiket-case|caseId|case)\s*[:=]\s*([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})/i;

const APPROVAL_PATTERN = /\b(approved|approve|lgtm|sign[- ]?off)\b/i;

function recordField(payload: Record<string, unknown>, key: string): Record<string, unknown> {
  const value = payload[key];
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

function stringField(payload: Record<string, unknown>, key: string): string | undefined {
  const value = payload[key];
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function extractCaseId(...sources: unknown[]): string | undefined {
  for (const source of sources) {
    if (typeof source !== 'string') continue;
    const match = source.match(CASE_ID_PATTERN);
    if (match?.[1]) return match[1];
  }
  return undefined;
}

function isApprovalMessage(text: string): boolean {
  return APPROVAL_PATTERN.test(text);
}

function normalizeSourceTime(value: unknown, fallback: Date): Date {
  if (typeof value !== 'string' && typeof value !== 'number') return fallback;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? fallback : parsed;
}

function deliveryId(metadata: Record<string, unknown> | undefined): string | undefined {
  if (!metadata) return undefined;
  const value = metadata.deliveryId;
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

export function normalizeSlackRawEvent(ctx: SlackRawEventContext): NormalizedOperationalEventOutput {
  const payload = ctx.payload;
  const event = recordField(payload, 'event');
  const eventType = stringField(payload, 'type') ?? ctx.sourceEventType;
  if (eventType === 'url_verification') {
    throw new Error('Unsupported Slack event for core normalization');
  }

  const nestedMessage = recordField(event, 'message');
  const message = Object.keys(nestedMessage).length > 0 ? nestedMessage : event;
  const text = stringField(message, 'text') ?? stringField(payload, 'text') ?? '';
  const caseId = extractCaseId(text, stringField(payload, 'caseId'));
  if (!caseId) throw new Error('Missing required field: caseId');

  const channel = stringField(message, 'channel') ?? stringField(event, 'channel') ?? stringField(payload, 'channel');
  const ts = stringField(message, 'ts') ?? stringField(event, 'ts') ?? stringField(payload, 'ts') ?? ctx.idempotencyKey;
  const user = stringField(recordField(message, 'user'), 'id') ?? stringField(message, 'user');
  const approved = isApprovalMessage(text);
  const occurredAt = normalizeSourceTime(Number(ts) ? Number(ts) * 1000 : ts, ctx.receivedAt);
  const delivery = deliveryId(ctx.metadata);
  const sourceObjectId = channel && ts ? `${channel}:${ts}` : ts;

  return {
    organizationId: ctx.organizationId,
    workspaceId: ctx.workspaceId ?? undefined,
    processId: ctx.processId ?? undefined,
    caseId,
    eventType: approved ? 'approval.recorded' : 'evidence.observed',
    sourceSystem: 'slack',
    sourceObjectId,
    actor: user ? { id: user } : {},
    subject: { type: 'slack_message', id: sourceObjectId, caseId, channel },
    occurredAt,
    correlationIds: [ctx.rawEventId, ctx.idempotencyKey],
    attributes: {
      channel,
      approved,
      deliveryId: delivery,
    },
    dedupeKey: `slack:message:${sourceObjectId}`,
    evidence: [
      {
        evidenceType: approved ? 'slack_approval' : 'slack_message',
        title: approved ? 'Slack approval message' : 'Slack message evidence',
        sourceObjectId,
        capturedAt: occurredAt,
        payload: {
          channel,
          textPreview: text.slice(0, 500),
          approved,
          user,
          deliveryId: delivery,
        },
        dedupeKey: `slack:evidence:${sourceObjectId}`,
      },
    ],
    intents: [
      {
        type: 'case.link_external_evidence',
        targetType: 'case',
        targetId: caseId,
        reason: 'Slack message produced evidence for a linked operational case.',
        attributes: {
          evidenceType: approved ? 'slack_approval' : 'slack_message',
          sourceObjectId,
        },
        idempotencyKey: `slack:intent:link:${sourceObjectId}:${caseId}`,
      },
    ],
  };
}

export const SLACK_ADAPTER_SOURCE_EVENT_TYPES = ['event_callback', 'message'] as const;
export const SLACK_ADAPTER_EVIDENCE_TYPES = ['slack_message', 'slack_approval'] as const;
