# Slack Notifications Extension

Send notifications via Slack channels and direct messages using OAuth 2.0 Bot Token.

## Features

- **Direct Messages**: Send notifications to individual Slack users
- **Channel Messages**: Post to Slack channels
- **Rich Formatting**: Support for Slack's mrkdwn, markdown, and HTML
- **Threading**: Reply to messages in threads
- **Attachments**: Support for Slack message attachments
- **Validation**: Pre-flight checks for channels and users
- **Error Handling**: Comprehensive error handling with retry guidance
- **Rate Limiting**: Automatic rate limit detection with retry-after

## Prerequisites

1. **Slack Workspace**: Admin access to install apps
2. **Slack App**: Create a Slack app with Bot Token Scopes:
   - `chat:write` - Send messages
   - `users:read` - Read user information
   - `channels:read` - List public channels
   - `groups:read` - List private channels
   - `im:write` - Send direct messages

## Setup

### 1. Create Slack App

1. Go to [Slack API Apps](https://api.slack.com/apps)
2. Click "Create New App" → "From scratch"
3. Enter app name and select workspace
4. Navigate to "OAuth & Permissions"
5. Add Bot Token Scopes (listed above)
6. Install app to workspace
7. Copy "Bot User OAuth Token" (starts with `xoxb-`)

### 2. Configure Extension

Create `.env` file:
```bash
SLACK_BOT_TOKEN=xoxb-your-bot-token-here
```

### 3. Install Dependencies

```bash
bundle install
```

## Development

```bash
# Run locally
bundle exec rackup -p 9292

# Run tests
bundle exec rspec

# Check code style
bundle exec rubocop
```

## Deployment

### Docker (GitHub Container Registry)

```bash
docker pull ghcr.io/kiket-dev/kiket-ext-slack:latest

docker run -p 9292:9292 \
  -e SLACK_BOT_TOKEN=xoxb-your-token \
  ghcr.io/kiket-dev/kiket-ext-slack:latest
```

## API Endpoints

### POST /notify

Send notification to Slack.

**Request:**
```json
{
  "message": "Hello from Kiket!",
  "channel_type": "channel",
  "channel_id": "C1234567890",
  "format": "mrkdwn"
}
```

**Response:**
```json
{
  "success": true,
  "message_id": "1234567890.123456",
  "delivered_at": "2025-11-09T12:00:00Z"
}
```

### POST /validate

Validate channel/user exists.

### GET /health

Health check endpoint.

## License

MIT License - see LICENSE file for details
