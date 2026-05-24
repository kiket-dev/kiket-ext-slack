# kiket-ext-slack

Slack evidence adapter for [Kiket](https://kiket.dev) — registers the extension manifest and re-exports the TypeScript normalizer from the monorepo.

## Layout

| Path | Purpose |
| ---- | ------- |
| `extension.yaml` | Platform extension manifest (repo root — not `.kiket/`) |
| `src/index.ts` | Re-exports `@kiket/slack-adapter` for packaging and tests |

Normalization logic lives in the Kiket monorepo at `packages/slack-adapter`. This submodule is the installable extension repo (`kiket-ext-slack`).

## Install on a workspace

Register the extension with the platform API:

```http
POST /platform/extensions
```

Configure credentials and an event source, then route Slack events to `/integrations/slack/webhook`. See the integration guide for full setup.

## Documentation

- [Slack adapter](https://docs.kiket.dev/docs/integrations/slack-adapter)

## Development (monorepo)

When checked out inside the Kiket workspace, install from the repo root:

```bash
pnpm install
pnpm --filter @kiket/ext-slack check
pnpm --filter @kiket/ext-slack test
```

Standalone CI in this repo validates `extension.yaml` and entrypoint presence only; build and tests run in the monorepo where `@kiket/slack-adapter` is linked via `workspace:*`.
