# frozen_string_literal: true

require 'kiket_sdk'
require 'rackup'
require 'json'
require 'net/http'
require 'uri'
require 'logger'

# Slack Notification Extension
# Handles sending notifications via Slack using OAuth 2.0 Bot Token
class SlackNotificationExtension
  REQUIRED_NOTIFY_SCOPES = %w[notifications:send].freeze
  REQUIRED_VALIDATE_SCOPES = %w[notifications:read].freeze

  class SlackAPIError < StandardError
    attr_reader :retry_after

    def initialize(message, retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end

  def initialize
    @sdk = KiketSDK.new
    @logger = Logger.new($stdout)
    setup_handlers
  end

  def app
    @sdk
  end

  private

  def setup_handlers
    # Send notification
    @sdk.register('slack.notify', version: 'v1', required_scopes: REQUIRED_NOTIFY_SCOPES) do |payload, context|
      handle_notify(payload, context)
    end

    # Validate channel configuration
    @sdk.register('slack.validate', version: 'v1', required_scopes: REQUIRED_VALIDATE_SCOPES) do |payload, context|
      handle_validate(payload, context)
    end
  end

  def handle_notify(payload, context)
    validate_notification_request!(payload)

    # Get Slack token from secrets (per-org or ENV fallback)
    token = context[:secret].call('SLACK_BOT_TOKEN')
    raise ArgumentError, 'Missing SLACK_BOT_TOKEN' if token.nil? || token.empty?

    result = case payload['channel_type']
             when 'dm'
               send_direct_message(payload, token)
             when 'channel'
               send_channel_message(payload, token)
             else
               raise ArgumentError, "Unsupported channel_type: #{payload['channel_type']}"
             end

    context[:endpoints].log_event('slack.message.sent', {
                                    channel_type: payload['channel_type'],
                                    org_id: context[:auth][:org_id]
                                  })

    {
      success: true,
      message_id: result[:message_id],
      delivered_at: Time.now.utc.iso8601
    }
  rescue ArgumentError => e
    @logger.error "Validation error: #{e.message}"
    { success: false, error: e.message }
  rescue SlackAPIError => e
    @logger.error "Slack API error: #{e.message}"
    { success: false, error: "Slack API error: #{e.message}", retry_after: e.retry_after }
  rescue StandardError => e
    @logger.error "Unexpected error: #{e.message}\n#{e.backtrace.join("\n")}"
    { success: false, error: 'Internal server error' }
  end

  def handle_validate(payload, context)
    token = context[:secret].call('SLACK_BOT_TOKEN')
    raise ArgumentError, 'Missing SLACK_BOT_TOKEN' if token.nil? || token.empty?

    case payload['channel_type']
    when 'dm'
      validate_user_exists(payload['recipient_id'], token)
    when 'channel'
      validate_channel_exists(payload['channel_id'], token)
    else
      raise ArgumentError, "Unsupported channel_type: #{payload['channel_type']}"
    end

    { valid: true, message: 'Channel configuration is valid' }
  rescue ArgumentError => e
    { valid: false, error: e.message }
  rescue SlackAPIError => e
    { valid: false, error: e.message }
  rescue StandardError => e
    @logger.error "Unexpected error: #{e.message}"
    { valid: false, error: 'Internal server error' }
  end

  # Validation helpers

  def validate_notification_request!(request)
    raise ArgumentError, 'message is required' if request['message'].nil? || request['message'].empty?
    raise ArgumentError, 'channel_type is required' if request['channel_type'].nil?

    case request['channel_type']
    when 'dm'
      raise ArgumentError, 'recipient_id is required for DM' if request['recipient_id'].nil?
    when 'channel'
      raise ArgumentError, 'channel_id is required for channel' if request['channel_id'].nil?
    end
  end

  # Slack API methods

  def send_direct_message(request, token)
    conversation = open_conversation(request['recipient_id'], token)

    send_message(
      channel: conversation[:channel_id],
      text: request['message'],
      format: request['format'],
      thread_id: request['thread_id'],
      attachments: request['attachments'],
      token: token
    )
  end

  def send_channel_message(request, token)
    send_message(
      channel: request['channel_id'],
      text: request['message'],
      format: request['format'],
      thread_id: request['thread_id'],
      attachments: request['attachments'],
      token: token
    )
  end

  def open_conversation(user_id, token)
    uri = URI('https://slack.com/api/conversations.open')

    http_request = Net::HTTP::Post.new(uri)
    http_request['Authorization'] = "Bearer #{token}"
    http_request['Content-Type'] = 'application/json'
    http_request.body = { users: user_id }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    data = handle_slack_response(response)
    { channel_id: data['channel']['id'] }
  end

  def send_message(channel:, text:, token:, format: nil, thread_id: nil, attachments: nil)
    uri = URI('https://slack.com/api/chat.postMessage')

    http_request = Net::HTTP::Post.new(uri)
    http_request['Authorization'] = "Bearer #{token}"
    http_request['Content-Type'] = 'application/json'

    payload = {
      channel: channel,
      text: format_message(text, format),
      mrkdwn: format != 'plain'
    }

    payload[:thread_ts] = thread_id if thread_id
    payload[:attachments] = attachments if attachments && !attachments.empty?

    http_request.body = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    data = handle_slack_response(response)
    { message_id: data['ts'] }
  end

  def validate_user_exists(user_id, token)
    uri = URI('https://slack.com/api/users.info')
    uri.query = URI.encode_www_form({ user: user_id })

    http_request = Net::HTTP::Get.new(uri)
    http_request['Authorization'] = "Bearer #{token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    handle_slack_response(response)
    true
  end

  def validate_channel_exists(channel_id, token)
    uri = URI('https://slack.com/api/conversations.info')
    uri.query = URI.encode_www_form({ channel: channel_id })

    http_request = Net::HTTP::Get.new(uri)
    http_request['Authorization'] = "Bearer #{token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    handle_slack_response(response)
    true
  end

  def format_message(message, format)
    case format
    when 'mrkdwn', nil
      message
    when 'plain'
      message
    when 'markdown'
      message
        .gsub(/\*\*(.+?)\*\*/, '*\1*')
        .gsub(/__(.+?)__/, '_\1_')
        .gsub(/~~(.+?)~~/, '~\1~')
    when 'html'
      message
        .gsub(%r{<br\s*/?>}, "\n")
        .gsub(%r{</?p>}, "\n")
        .gsub(%r{<strong>(.*?)</strong>}, '*\1*')
        .gsub(%r{<b>(.*?)</b>}, '*\1*')
        .gsub(%r{<em>(.*?)</em>}, '_\1_')
        .gsub(%r{<i>(.*?)</i>}, '_\1_')
        .gsub(%r{<code>(.*?)</code>}, '`\1`')
        .gsub(%r{<del>(.*?)</del>}, '~\1~')
        .gsub(/<[^>]+>/, '')
    else
      message
    end
  end

  def handle_slack_response(response)
    unless response.is_a?(Net::HTTPSuccess)
      case response
      when Net::HTTPTooManyRequests
        retry_after = response['Retry-After']&.to_i || 60
        raise SlackAPIError.new('Rate limit exceeded', retry_after: retry_after)
      when Net::HTTPUnauthorized
        raise SlackAPIError, 'Unauthorized: Invalid or expired token'
      when Net::HTTPForbidden
        raise SlackAPIError, 'Forbidden: Insufficient permissions'
      else
        raise SlackAPIError, "Slack API error: #{response.code} #{response.message}"
      end
    end

    data = JSON.parse(response.body)

    unless data['ok']
      error = data['error'] || 'unknown_error'
      case error
      when 'ratelimited'
        retry_after = data['retry_after'] || 60
        raise SlackAPIError.new('Rate limit exceeded', retry_after: retry_after)
      when 'token_revoked', 'invalid_auth'
        raise SlackAPIError, "Authentication failed: #{error}"
      when 'channel_not_found', 'user_not_found'
        raise SlackAPIError, "Not found: #{error}"
      when 'not_in_channel'
        raise SlackAPIError, 'Bot not in channel'
      else
        raise SlackAPIError, "Slack error: #{error}"
      end
    end

    data
  end
end

# Run the extension
if __FILE__ == $PROGRAM_NAME
  extension = SlackNotificationExtension.new

  Rackup::Handler.get(:puma).run(
    extension.app,
    Host: ENV.fetch('HOST', '0.0.0.0'),
    Port: ENV.fetch('PORT', 8080).to_i,
    Threads: '0:16'
  )
end
