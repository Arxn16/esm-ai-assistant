# Ai::Provider - base contract + factory for swappable AI chat backends.
#
# Concrete adapters implement:
#   #chat(messages, opts = {}) -> { :role => 'assistant', :content => String }
#   #models                    -> [String, ...]   (available model ids, for the UI dropdown)
# where `messages` is an Array of { :role => 'system'|'user'|'assistant', :content => String }.
#
# Engine selection is config-driven; the client may only send a KEY (local/cloud) and a model
# id from the live list - NEVER URLs or API keys (those stay server-side). Top-level `Ai::`
# namespace is used on purpose to avoid colliding with the `Esm` ActiveRecord model.
module Ai
  class Error < StandardError; end

  class Provider
    DEFAULT = 'ollama'.freeze

    def chat(messages, opts = {})
      raise NotImplementedError, "#{self.class} must implement #chat"
    end

    # Available model names for this provider (for the UI dropdown). Default: none.
    def models
      []
    end

    # Factory: engine/name -> adapter instance.
    #   local  -> Ollama (on-prem)
    #   cloud  -> OpenAI-compatible (OpenRouter by default; also Groq, etc. via AI_CLOUD_URL)
    def self.for(name = nil)
      key = (name || ENV['AI_PROVIDER'] || DEFAULT).to_s.strip.downcase
      case key
      when 'ollama', 'local'
        Ai::Ollama.new
      when 'cloud', 'openrouter', 'groq', 'openai_compat'
        Ai::OpenaiCompat.new
      else
        Ai::Ollama.new
      end
    end
  end
end
