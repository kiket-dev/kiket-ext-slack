# frozen_string_literal: true

require "sinatra/base"
require "json"
require "net/http"
require "uri"
require "logger"

# Slack Notification Extension
# Handles sending notifications via Slack using OAuth 2.0 Bot Token
class SlackNotificationExtension < Sinatra::Base
  configure do
    set :logging, true
    set :logger, Logger.new($stdout)
  end

  # Health check endpoint
  get "/health" do
    content_type :json
    {
      status: "healthy",
      service: "slack-notifications",
      version: "1.0.0",
      timestamp: Time.now.utc.iso8601
    }.to_json
  end

  # Send notification endpoint
  post "/notify" do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read, symbolize_names: true)

      # Validate required fields
      validate_notification_request!(request_body)

      # Send message based on channel type
      result = case request_body[:channel_type]
      when "dm"
        send_direct_message(request_body)
      when "channel"
        send_channel_message(request_body)
      else
        raise ArgumentError, "Unsupported channel_type: #{request_body[:channel_type]}"
      end

      status 200
      {
        success: true,
        message_id: result[:message_id],
        delivered_at: Time.now.utc.iso8601
      }.to_json

    rescue JSON::ParserError => e
      logger.error "Invalid JSON: #{e.message}"
      status 400
      { success: false, error: "Invalid JSON in request body" }.to_json

    rescue ArgumentError => e
      logger.error "Validation error: #{e.message}"
      status 400
      { success: false, error: e.message }.to_json

    rescue SlackAPIError => e
      logger.error "Slack API error: #{e.message}"
      status 502
      {
        success: false,
        error: "Slack API error: #{e.message}",
        retry_after: e.retry_after
      }.to_json

    rescue StandardError => e
      logger.error "Unexpected error: #{e.message}\n#{e.backtrace.join("\n")}"
      status 500
      { success: false, error: "Internal server error" }.to_json
    end
  end

  # Validate channel configuration
  post "/validate" do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read, symbolize_names: true)

      # Validate based on type
      case request_body[:channel_type]
      when "dm"
        validate_user_exists(request_body[:recipient_id])
      when "channel"
        validate_channel_exists(request_body[:channel_id])
      else
        raise ArgumentError, "Unsupported channel_type: #{request_body[:channel_type]}"
      end

      status 200
      {
        valid: true,
        message: "Channel configuration is valid"
      }.to_json

    rescue JSON::ParserError => e
      status 400
      { valid: false, error: "Invalid JSON in request body" }.to_json

    rescue ArgumentError => e
      status 400
      { valid: false, error: e.message }.to_json

    rescue SlackAPIError => e
      status 200
      { valid: false, error: e.message }.to_json

    rescue StandardError => e
      logger.error "Unexpected error: #{e.message}"
      status 500
      { valid: false, error: "Internal server error" }.to_json
    end
  end

  private

  # Custom error for Slack API issues
  class SlackAPIError < StandardError
    attr_reader :retry_after

    def initialize(message, retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end

  # Validate notification request has required fields
  def validate_notification_request!(request)
    raise ArgumentError, "message is required" if request[:message].nil? || request[:message].empty?
    raise ArgumentError, "channel_type is required" if request[:channel_type].nil?

    case request[:channel_type]
    when "dm"
      raise ArgumentError, "recipient_id is required for DM" if request[:recipient_id].nil?
    when "channel"
      raise ArgumentError, "channel_id is required for channel" if request[:channel_id].nil?
    end
  end

  # Get Slack bot token from environment
  def slack_token
    token = ENV["SLACK_BOT_TOKEN"]
    raise ArgumentError, "Missing SLACK_BOT_TOKEN" if token.nil? || token.empty?

    token
  end

  # Send direct message to a Slack user
  def send_direct_message(request)
    # Open conversation with user first
    conversation = open_conversation(request[:recipient_id])

    # Send message to conversation
    send_message(
      channel: conversation[:channel_id],
      text: request[:message],
      format: request[:format],
      thread_id: request[:thread_id],
      attachments: request[:attachments]
    )
  end

  # Send message to a Slack channel
  def send_channel_message(request)
    send_message(
      channel: request[:channel_id],
      text: request[:message],
      format: request[:format],
      thread_id: request[:thread_id],
      attachments: request[:attachments]
    )
  end

  # Open a direct message conversation with a user
  def open_conversation(user_id)
    uri = URI("https://slack.com/api/conversations.open")

    http_request = Net::HTTP::Post.new(uri)
    http_request["Authorization"] = "Bearer #{slack_token}"
    http_request["Content-Type"] = "application/json"
    http_request.body = { users: user_id }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    data = handle_slack_response(response)
    { channel_id: data["channel"]["id"] }
  end

  # Send message to Slack
  def send_message(channel:, text:, format: nil, thread_id: nil, attachments: nil)
    uri = URI("https://slack.com/api/chat.postMessage")

    http_request = Net::HTTP::Post.new(uri)
    http_request["Authorization"] = "Bearer #{slack_token}"
    http_request["Content-Type"] = "application/json"

    payload = {
      channel: channel,
      text: format_message(text, format),
      mrkdwn: format != "plain"
    }

    # Add thread support
    payload[:thread_ts] = thread_id if thread_id

    # Add attachments if provided
    payload[:attachments] = attachments if attachments && !attachments.empty?

    http_request.body = payload.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    data = handle_slack_response(response)
    { message_id: data["ts"] }
  end

  # Validate that a Slack user exists
  def validate_user_exists(user_id)
    uri = URI("https://slack.com/api/users.info")
    uri.query = URI.encode_www_form({ user: user_id })

    http_request = Net::HTTP::Get.new(uri)
    http_request["Authorization"] = "Bearer #{slack_token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    handle_slack_response(response)
    true
  end

  # Validate that a Slack channel exists
  def validate_channel_exists(channel_id)
    uri = URI("https://slack.com/api/conversations.info")
    uri.query = URI.encode_www_form({ channel: channel_id })

    http_request = Net::HTTP::Get.new(uri)
    http_request["Authorization"] = "Bearer #{slack_token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    handle_slack_response(response)
    true
  end

  # Format message based on requested format
  def format_message(message, format)
    case format
    when "mrkdwn", nil
      message # Slack's default markdown format
    when "plain"
      message # Plain text, disable markdown in API call
    when "markdown"
      # Convert standard markdown to Slack mrkdwn
      message
        .gsub(/\*\*(.+?)\*\*/, '*\1*')  # Bold
        .gsub(/__(.+?)__/, '_\1_')      # Italic
        .gsub(/~~(.+?)~~/, '~\1~')      # Strikethrough
    when "html"
      # Convert HTML to Slack mrkdwn
      message
        .gsub(/<br\s*\/?>/, "\n")
        .gsub(/<\/?p>/, "\n")
        .gsub(/<strong>(.*?)<\/strong>/, '*\1*')
        .gsub(/<b>(.*?)<\/b>/, '*\1*')
        .gsub(/<em>(.*?)<\/em>/, '_\1_')
        .gsub(/<i>(.*?)<\/i>/, '_\1_')
        .gsub(/<code>(.*?)<\/code>/, '`\1`')
        .gsub(/<del>(.*?)<\/del>/, '~\1~')
        .gsub(/<[^>]+>/, "") # Remove remaining tags
    else
      message
    end
  end

  # Handle Slack API response
  def handle_slack_response(response)
    unless response.is_a?(Net::HTTPSuccess)
      case response
      when Net::HTTPTooManyRequests
        retry_after = response["Retry-After"]&.to_i || 60
        raise SlackAPIError.new("Rate limit exceeded", retry_after: retry_after)
      when Net::HTTPUnauthorized
        raise SlackAPIError, "Unauthorized: Invalid or expired token"
      when Net::HTTPForbidden
        raise SlackAPIError, "Forbidden: Insufficient permissions"
      else
        raise SlackAPIError, "Slack API error: #{response.code} #{response.message}"
      end
    end

    data = JSON.parse(response.body)

    unless data["ok"]
      error = data["error"] || "unknown_error"
      case error
      when "ratelimited"
        retry_after = data["retry_after"] || 60
        raise SlackAPIError.new("Rate limit exceeded", retry_after: retry_after)
      when "token_revoked", "invalid_auth"
        raise SlackAPIError, "Authentication failed: #{error}"
      when "channel_not_found", "user_not_found"
        raise SlackAPIError, "Not found: #{error}"
      when "not_in_channel"
        raise SlackAPIError, "Bot not in channel"
      else
        raise SlackAPIError, "Slack error: #{error}"
      end
    end

    data
  end
end
