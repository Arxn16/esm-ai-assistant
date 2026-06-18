# Ai::Provider - base contract + factory for swappable AI chat backends.
#
# Concrete adapters (Ollama now; OpenAI / Claude later) implement
#   #chat(messages, opts = {}) -> { :role => 'assistant', :content => String }
# where `messages` is an Array of { :role => 'system'|'user'|'assistant', :content => String }.
#
# Provider selection is config-driven (ENV['AI_PROVIDER'], default 'ollama') so the
# backend can be swapped without touching the controller or the widget.
#
# Lives under lib/ (on autoload_paths via lib/esm_essential.rb). Top-level `Ai`
# namespace is used on purpose to avoid colliding with the `Esm` ActiveRecord model.
module Ai
  class Error < StandardError; end

  class Provider
    DEFAULT = 'ollama'.freeze

    # Subclasses must override. Returns { :role => 'assistant', :content => String }.
    def chat(messages, opts = {})
      raise NotImplementedError, "#{self.class} must implement #chat"
    end

    # Factory: name (or ENV) -> adapter instance. Unknown names fall back to Ollama.
    # The provider is ALWAYS chosen server-side; never trust a client-supplied value.
    def self.for(name = nil)
      key = (name || ENV['AI_PROVIDER'] || DEFAULT).to_s.strip.downcase
      case key
      when 'ollama' then Ai::Ollama.new
      # Future:
      # when 'openai' then Ai::OpenAi.new
      # when 'claude' then Ai::Claude.new
      else
        Ai::Ollama.new
      end
    end
  end
end
