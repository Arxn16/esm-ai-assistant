# Ai::Ollama - on-prem / localhost chat adapter using Ruby stdlib Net::HTTP only.
# No external gems. Ruby 2.3 / Rails 4.2 compatible.
#
# Config (ENV, with safe defaults for Docker Desktop reaching a host-run Ollama):
#   OLLAMA_URL   base url            default 'http://host.docker.internal:11434'
#   AI_MODEL     model name          default 'qwen3:1.7b'
#   AI_TIMEOUT   read timeout (secs)  default 180
#
# The base URL and model are server-side config only - never derived from client input.
#
# Telemetry: every call logs METADATA ONLY (provider/model/mode/ctx/predict/timeout/
# prompt-size-in-chars/elapsed/status). No message or prompt contents, no records, no PHI.
require 'net/http'
require 'uri'
require 'json'

module Ai
  class Ollama < Provider
    DEFAULT_URL     = 'http://host.docker.internal:11434'.freeze
    DEFAULT_MODEL   = 'qwen3:1.7b'.freeze
    OPEN_TIMEOUT    = 5
    DEFAULT_TIMEOUT = 180
    ALLOWED_ROLES   = %w{system user assistant}.freeze

    def initialize(opts = {})
      @base_url = (opts[:url]     || ENV['OLLAMA_URL'] || DEFAULT_URL).to_s.sub(%r{/+\z}, '')
      @model    = (opts[:model]   || ENV['AI_MODEL']  || DEFAULT_MODEL).to_s
      @timeout  = (opts[:timeout] || ENV['AI_TIMEOUT'] || DEFAULT_TIMEOUT).to_i
    end

    def chat(messages, opts = {})
      t0           = Time.now
      options      = opts[:options].is_a?(Hash) ? opts[:options] : {}
      mode         = opts[:mode]
      read_to      = (opts[:timeout] || @timeout)
      # prompt SIZE only (char count) - never the contents.
      prompt_chars = Array(messages).inject(0) { |n, m| n + (m[:content] || m['content']).to_s.length }

      uri = URI.parse("#{@base_url}/api/chat")
      payload = {
        :model    => (opts[:model] || @model),
        :messages => normalize(messages),
        :stream   => false,
        :think    => false # qwen3: suppress <think> reasoning (ignored by older Ollama)
      }
      payload[:options] = options unless options.empty?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = (uri.scheme == 'https')
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = read_to

      req = Net::HTTP::Post.new(uri.request_uri)
      req['Content-Type'] = 'application/json'
      req.body = JSON.generate(payload)

      res = http.request(req)
      raise Ai::Error, "http_#{res.code}" unless res.is_a?(Net::HTTPSuccess)

      data    = JSON.parse(res.body)
      content = data.fetch('message', {}).fetch('content', '').to_s
      telemetry(mode, options, read_to, prompt_chars, t0, 'ok')
      { :role => 'assistant', :content => strip_think(content) }

    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      telemetry(mode, options, read_to, prompt_chars, t0, 'timeout')
      raise Ai::Error, 'timeout'
    rescue Errno::ECONNREFUSED
      telemetry(mode, options, read_to, prompt_chars, t0, 'error', 'connection refused')
      raise Ai::Error, 'unreachable'
    rescue Errno::EHOSTUNREACH, SocketError
      telemetry(mode, options, read_to, prompt_chars, t0, 'error', 'host unreachable')
      raise Ai::Error, 'unreachable'
    rescue JSON::ParserError
      telemetry(mode, options, read_to, prompt_chars, t0, 'error', 'bad response')
      raise Ai::Error, 'bad_response'
    rescue Ai::Error => e
      telemetry(mode, options, read_to, prompt_chars, t0, 'error', e.message)
      raise
    end

    # Locally-pulled Ollama models (GET /api/tags) for the model dropdown.
    def models
      uri  = URI.parse("#{@base_url}/api/tags")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = (uri.scheme == 'https')
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = 10
      res  = http.request(Net::HTTP::Get.new(uri.request_uri))
      return [] unless res.is_a?(Net::HTTPSuccess)
      data = JSON.parse(res.body)
      Array(data['models']).map { |m| m['name'] }.compact
    rescue
      []
    end

    private

    def normalize(messages)
      Array(messages).map do |m|
        role = (m[:role] || m['role']).to_s
        role = 'user' unless ALLOWED_ROLES.include?(role)
        { :role => role, :content => (m[:content] || m['content']).to_s }
      end
    end

    # Remove <think>...</think> blocks some qwen3 builds still emit inside content.
    def strip_think(text)
      text.gsub(/<think>.*?<\/think>/m, '').strip
    end

    # METADATA-ONLY telemetry. No message/prompt contents, no records, no PHI.
    def telemetry(mode, options, timeout, prompt_chars, t0, status, error = nil)
      elapsed = (Time.now - t0).round(1)
      line = "[AI] provider=ollama model=#{@model}"
      line += " mode=#{mode}" if mode
      if status == 'error'
        line += " status=error error=\"#{error}\""
      else
        ctx  = options[:num_ctx]     || options['num_ctx']     || 'default'
        pred = options[:num_predict] || options['num_predict'] || 'default'
        line += " ctx=#{ctx} predict=#{pred} timeout=#{timeout} prompt=#{prompt_chars} elapsed=#{elapsed}s status=#{status}"
      end
      log_info(line)
    end

    def log_info(msg)
      Ai::Provider.log(msg)
    end
  end
end
