# AI Assistant - backend for the global chat widget (app/views/layouts/_ai_assistant.html.erb).
#
# Subclasses EsmController to reuse the existing context_filter auth/session gate.
# Delegates chat to a swappable provider adapter under lib/ai/ (Ollama by default).
#
# Modes (Ai::Modes): chat / project / code / agent / documentation. Each selects a
# system prompt and an optional context strategy. Context files are read ONLY through
# Ai::Context, which restricts reads to a server-side allowlist (no path traversal,
# no secret files). The assistant never writes files or executes anything - text only.
#
# Chat history is client-side only (posted per request); nothing is persisted.
class AiAssistantController < EsmController

  MAX_MESSAGE_CHARS = 4000
  MAX_HISTORY_TURNS = 10
  RATE_LIMIT        = 15  # requests
  RATE_WINDOW       = 60  # seconds
  INJECT_MAX_BYTES  = 8 * 1024  # cap injected file context to fit num_ctx 4096

  def message
    return render_reply('Please sign in to use the AI Assistant.', :unauthorized) unless @current_user

    if rate_limited?(@current_user.id)
      return render_reply('You are sending messages too quickly. Please wait a moment.', 429)
    end

    text = params[:message].to_s.strip
    return render_reply('Please type a message.') if text == ''
    text = text[0, MAX_MESSAGE_CHARS]

    mode = Ai::Modes.valid?(params[:mode]) ? params[:mode].to_s : Ai::Modes::DEFAULT
    spec = Ai::Modes.get(mode)

    messages = [{ :role => 'system', :content => spec[:system] }]

    proj = project_block(params[:project_id])
    messages << { :role => 'system', :content => proj } if proj

    ctx = context_block(spec[:context], params[:path])
    messages << { :role => 'system', :content => ctx } if ctx

    messages.concat(history_from_params)
    messages << { :role => 'user', :content => text }

    options = {}
    options[:num_ctx]     = spec[:num_ctx]     if spec[:num_ctx]
    options[:num_predict] = spec[:num_predict] if spec[:num_predict]
    opts = { :mode => mode }
    opts[:options] = options unless options.empty?

    # Telemetry (metadata only - no message/prompt contents, no PHI).
    Rails.logger.info("[AI] mode=#{mode} project=#{params[:project_id]} user=#{@current_user.id}")
    reply = Ai::Provider.for(server_provider).chat(messages, opts)
    render_reply(reply[:content].to_s)

  rescue Ai::Error => e
    render_reply(friendly_error(e.message), 502)
  rescue => e
    # Never leak internals; production renders full error pages otherwise.
    render_reply('Sorry, the assistant is unavailable right now.', :internal_server_error)
  end

  private

  def render_reply(content, status = :ok)
    render :json => { :role => 'assistant', :content => content }, :status => status
  end

  # Provider is chosen server-side only (default ollama) - never trust the client.
  def server_provider
    ENV['AI_PROVIDER'] || 'ollama'
  end

  # Definitions-only metadata summary of the selected project = primary context for ALL
  # modes. ACL-scoped (Ai::ProjectContext). Reads MySQL metadata only - never MongoDB records.
  def project_block(project_id)
    return nil if project_id.to_s == ''
    summary = Ai::ProjectContext.summary(@current_user, project_id)
    return nil unless summary
    "=== SELECTED PROJECT (definitions only; no real records) ===\n#{summary}\n=== END PROJECT ===\n\n" \
    "Treat this project as the primary context. Do not assume any industry/domain beyond what this metadata indicates."
  end

  # Build a context block from an ALLOWLISTED file, appropriate to the mode.
  # Double-checks the path against the mode's list AND Ai::Context's own guard.
  def context_block(kind, path)
    return nil unless kind == :docs || kind == :code
    rel = path.to_s
    return nil if rel == ''

    allowed = (kind == :docs) ? Ai::Context.project_files : Ai::Context.code_files
    return nil unless allowed.include?(rel)

    content = Ai::Context.read(rel)
    return nil unless content
    if content.bytesize > INJECT_MAX_BYTES
      marker  = (kind == :docs) ? "\n[DOCUMENT TRUNCATED]" : "\n[FILE TRUNCATED]"
      content = content.byteslice(0, INJECT_MAX_BYTES).to_s + marker
    end
    "=== FILE: #{rel} ===\n#{content}\n=== END FILE ===\n\n" \
    "Use the file above to answer. Cite #{rel}:line where relevant."
  end

  # Validate + cap client history (sent as a JSON string). Only user/assistant turns kept.
  def history_from_params
    raw = params[:history].to_s
    return [] if raw.empty?
    parsed = (JSON.parse(raw) rescue [])
    return [] unless parsed.is_a?(Array)

    turns = parsed.last(MAX_HISTORY_TURNS).map do |m|
      next nil unless m.is_a?(Hash)
      role = m['role'].to_s
      role = 'user' unless %w{user assistant}.include?(role)
      { :role => role, :content => m['content'].to_s[0, MAX_MESSAGE_CHARS].to_s }
    end
    turns.compact.reject { |m| m[:content].strip == '' }
  end

  # Simple in-process fixed-window throttle. A global survives Rails' per-request class
  # reloading in development; safe because the deployed server (Thin) is single-threaded.
  def rate_limited?(uid)
    now    = Time.now.to_i
    store  = ($esmai_rate ||= {})
    bucket = (store[uid] ||= [])
    bucket.reject! { |t| t < now - RATE_WINDOW }
    return true if bucket.size >= RATE_LIMIT
    bucket << now
    false
  end

  def friendly_error(code)
    case code
    when 'timeout'     then 'The assistant took too long to respond. Please try again.'
    when 'unreachable' then 'The AI service is not reachable right now.'
    else 'Sorry, the assistant is unavailable right now.'
    end
  end

end
