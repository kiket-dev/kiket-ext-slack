# Getting Started with Slack Notifications

This guide walks you through setting up the Slack extension to send notifications from your Kiket workflows.

## Prerequisites

- A Slack workspace where you have admin permissions
- A Kiket project with workflows configured

## Step 1: Create a Slack App

1. Go to [Slack API Apps](https://api.slack.com/apps)
2. Click **Create New App** → **From scratch**
3. Enter an app name (e.g., "Kiket Notifications") and select your workspace
4. Click **Create App**

## Step 2: Configure Bot Permissions

1. In your app settings, go to **OAuth & Permissions**
2. Under **Bot Token Scopes**, add these permissions:
   - `chat:write` - Send messages as the bot
   - `users:read` - Look up user information
   - `channels:read` - List public channels
   - `groups:read` - List private channels (if needed)
   - `im:write` - Send direct messages

3. Click **Install to Workspace** and authorize the app
4. Copy the **Bot User OAuth Token** (starts with `xoxb-`)

## Step 3: Install the Extension in Kiket

1. Go to **Organization Settings → Extensions → Marketplace**
2. Find "Slack Notifications" and click **Install**
3. Paste your Bot User OAuth Token in the configuration
4. Select the default channel for notifications (optional)

## Step 4: Configure Workflow Notifications

Add Slack notifications to your workflow automations:

```yaml
automations:
  - name: notify_on_issue_created
    trigger:
      event: issue.created
    actions:
      - extension: dev.kiket.ext.slack
        command: slack.sendMessage
        params:
          channel: "#project-updates"
          template: issue_created_message
```

## Step 5: Customize Message Templates

The extension includes default templates, but you can customize them:

1. Go to **Project Settings → Extensions → Slack**
2. Edit the message templates using Liquid syntax
3. Available variables include `issue`, `user`, `project`, and `transition`

Example custom template:

```liquid
:ticket: *New Issue*: {{ issue.title }}
Priority: {{ issue.priority | default: "Normal" }}
Assigned to: {{ issue.assignee.name | default: "Unassigned" }}
<{{ issue.url }}|View in Kiket>
```

## Next Steps

- [View example workflows](./examples/)
- Configure SLA breach alerts
- Set up approval workflows with interactive buttons
