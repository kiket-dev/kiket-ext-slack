# kiket-ext-slack

Slack evidence adapter for [Kiket](https://kiket.dev) — registers the platform manifest and re-exports the TypeScript normalizer from the monorepo.

## Layout

| Path | Purpose |
| ---- | ------- |
| `kiket-extension.yaml` | Kiket platform extension manifest (repo root) |
| `src/index.ts` | Re-exports `@kiket/slack-adapter` for packaging and tests |

Normalization logic lives in the Kiket monorepo at `packages/slack-adapter`. Process templates live in `definitions/` — not in this repo.

## Install on a workspace

Register the extension with the platform API:

```http
POST /platform/extensions
```

Configure credentials and an evidence source, then route Slack events to `/integrations/slack/webhook`. See the integration guide for full setup.

## Documentation

- [Extension adapters (manifest + layout)](https://docs.kiket.dev/docs/compliance/extension-adapters)
- [Slack adapter](https://docs.kiket.dev/docs/integrations/slack-adapter)

## Development (monorepo)

When checked out inside the Kiket workspace, install from the repo root:

```bash
pnpm install
pnpm --filter @kiket/ext-slack check
pnpm --filter @kiket/ext-slack test
```

Standalone CI in this repo validates `kiket-extension.yaml` and entrypoint presence; build and tests run in the monorepo where `@kiket/slack-adapter` is linked via `workspace:*`.
