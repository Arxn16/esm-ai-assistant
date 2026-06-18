# Ai::OpenaiCompat - Cloud chat adapter for any OpenAI-compatible API (OpenRouter, Groq, ...).
# Ruby 2.3 / Rails 4.2 compatible; stdlib Net::HTTP only. No external gems.
#
# Config (ENV; set in .env which is gitignored - NEVER commit the key):
#   AI_CLOUD_URL    base url   default 'https://openrouter.ai/api/v1'
#   AI_CLOUD_KEY    API key    (if empty -> raises 'cloud_not_configured')
#   AI_CLOUD_MODEL  default model id
#   AI_TIMEOUT      read timeout secs (shared); falls back to DEFAULT_TIMEOUT
#
# Definitions-only still applies (the controller never sends real records). base_url + key
# are server-side only; the client may only pick a model id from the live list.
require 'net/http'
require 'uri'
require 'json'

module Ai
  class OpenaiCompat < Provider
    DEFAULT_URL     = 'https://openrouter.ai/api/v1'.freeze
    DEFAULT_MODEL   = 'deepseek/deepseek-chat-v3-0324:free'.freeze
    OPEN_TIMEOUT    = 5
    DEFAULT_TIMEOUT = 90
    ALLOWED_ROLES   = %w{system user assistant}.freeze

    def initialize(opts = {})
      @base_url = (opts[:url]   || ENV['AI_CLOUD_URL']   || DEFAULT_URL).to_s.sub(%r{/+\z}, '')
      @key      = (opts[:key]   || ENV['AI_CLOUD_KEY']).to_s
      @model    = (opts[:model] || ENV['AI_CLOUD_MODEL'] || DEFAULT_MODEL).to_s
      @timeout  = (opts[:timeout] || ENV['AI_TIMEOUT'] || DEFAULT_TIMEOUT).to_i
    end

    def configured?
      !@key.strip.empty?
    end

    def chat(messages, opts = {})
      t0           = Time.now
      options      = opts[:options].is_a?(Hash) ? opts[:options] : {}
      mode         = opts[:mode]
      model        = (opts[:model].to_s.strip != '') ? opts[:model].to_s.strip : @model
      read_to      = (opts[:timeout] || @timeout)
      prompt_chars = Array(messages).inject(0) { |n, m| n + (m[:content] || m['content']).to_s.length }

      unless configured?
        telemetry(mode, model, read_to, prompt_chars, t0, 'error', 'cloud_not_configured')
        raise Ai::Error, 'cloud_not_configured'
      end

      uri  = URI.parse("#{@base_url}/chat/completions")
      body = { :model => model, :messages => normalize(messages) }
      body[:max_tokens] = options[:num_predict] if options[:num_predict]

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = (uri.scheme == 'https')
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = read_to

      req = Net::HTTP::Post.new(uri.request_uri)
      req['Content-Type']  = 'application/json'
      req['Authorization'] = "Bearer #{@key}"
      req.body = JSON.generate(body)

      res = http.request(req)
      raise Ai::Error, "http_#{res.code}" unless res.is_a?(Net::HTTPSuccess)

      data    = JSON.parse(res.body)
      choice  = (data['choices'] || [{}])[0] || {}
      content = ((choice['message'] || {})['content']).to_s
      telemetry(mode, model, read_to, prompt_chars, t0, 'ok')
      { :role => 'assistant', :content => content.strip }

    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      telemetry(mode, model, read_to, prompt_chars, t0, 'timeout')
      raise Ai::Error, 'timeout'
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
      telemetry(mode, model, read_to, prompt_chars, t0, 'error', 'unreachable')
      raise Ai::Error, 'unreachable'
    rescue JSON::ParserError
      telemetry(mode, model, read_to, prompt_chars, t0, 'error', 'bad response')
      raise Ai::Error, 'bad_response'
    rescue Ai::Error => e
      telemetry(mode, model, read_to, prompt_chars, t0, 'error', e.message)
      raise
    end

    # Live model ids from the provider (GET /models), for the dropdown. [] if not configured.
    def models
      return [] unless configured?
      uri  = URI.parse("#{@base_url}/models")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = (uri.scheme == 'https')
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = 12
      req = Net::HTTP::Get.new(uri.request_uri)
      req['Authorization'] = "Bearer #{@key}"
      res = http.request(req)
      return [] unless res.is_a?(Net::HTTPSuccess)
      data = JSON.parse(res.body)
      Array(data['data']).map { |m| m['id'] }.compact
    rescue
      []
    end

    private

    def provider_label
      return 'ollama_cloud' if @base_url.include?('ollama.com')
      return 'openrouter'   if @base_url.include?('openrouter')
      return 'groq'         if @base_url.include?('groq')
      'cloud'
    end

    def normalize(messages)
      Array(messages).map do |m|
        role = (m[:role] || m['role']).to_s
        role = 'user' unless ALLOWED_ROLES.include?(role)
        { :role => role, :content => (m[:content] || m['content']).to_s }
      end
    end

    # METADATA-ONLY telemetry (no message/prompt contents, no PHI).
    def telemetry(mode, model, timeout, prompt_chars, t0, status, error = nil)
      elapsed = (Time.now - t0).round(1)
      line = "[AI] provider=#{provider_label} model=#{model}"
      line += " mode=#{mode}" if mode
      if status == 'error'
        line += " status=error error=\"#{error}\""
      else
        line += " timeout=#{timeout} prompt=#{prompt_chars} elapsed=#{elapsed}s status=#{status}"
      end
      Ai::Provider.log(line)
    end
  end
end
