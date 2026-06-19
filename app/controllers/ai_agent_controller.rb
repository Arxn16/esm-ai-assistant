# AI Agent - HTTP surface for the ESM tool registry (Ai::Tools) and agent loop (Ai::Agent).
#
# Phase 1 scope: READ tools only execute. Write tools are returned as PROPOSALS (never run here)
# until the approval/execute layer is built. Subclasses EsmController -> reuses auth + keeps CSRF.
class AiAgentController < EsmController

  # GET /ai_agent/tools - list the registered tools (metadata only).
  def tools
    return deny unless @current_user
    render :json => { :ok => true, :tools => Ai::Tools.catalog }
  end

  # POST /ai_agent/run  { tool, args } - run ONE tool directly. Read tools only for now.
  def run
    return deny unless @current_user
    tool = Ai::Tools.find(params[:tool])
    return render(:json => { :ok => false, :error => 'unknown tool' }, :status => 404) unless tool
    unless tool[:risk] == :read
      return render(:json => { :ok => false, :error => 'เครื่องมือนี้ยังไม่เปิด (เป็น write ต้องผ่านการอนุมัติ)' }, :status => 403)
    end
    render :json => { :ok => true, :tool => tool[:name], :result => Ai::Tools.run(params[:tool], args_hash) }
  rescue ActiveRecord::RecordNotFound
    render :json => { :ok => false, :error => 'ไม่พบข้อมูล' }, :status => 404
  rescue => e
    render :json => { :ok => false, :error => e.message }, :status => 500
  end

  # POST /ai_agent/ask  { message } - natural language -> multi-step PLAN.
  # All-read plan: executed now (mode:result). Any write: returned as a plan to approve (mode:proposal).
  def ask
    return deny unless @current_user
    msg = params[:message].to_s

    # Greeting / chit-chat -> answer warmly, skip the planner (nothing to plan; would otherwise
    # surface a scary "วางแผนไม่สำเร็จ"). Also avoids a slow LLM round-trip for "hi".
    if Ai::Agent.smalltalk?(msg)
      return render(:json => { :ok => true, :mode => 'info', :message => Ai::Agent.intro_message })
    end

    engine = (params[:engine].to_s.strip.downcase == 'cloud') ? 'cloud' : 'ollama'
    Ai::Provider.log("[AI-AGENT] ask user=#{@current_user.id} engine=#{engine}")
    pl = Ai::Agent.plan(msg, :engine => engine, :model => params[:model])

    # Couldn't turn the request into a runnable plan -> guide the user instead of erroring out.
    unless pl[:ok]
      return render(:json => { :ok => true, :mode => 'info',
        :message => "ผมยังแปลงข้อความนี้เป็นแผนงานไม่ได้ครับ ลองสั่งให้ชัดขึ้น (ระบุเลขเอกสาร/โปรเจกต์)\n\n" + Ai::Agent.intro_message })
    end

    if pl[:has_write]
      render :json => { :ok => true, :mode => 'proposal', :steps => pl[:steps] }
    else
      results = Ai::Agent.execute_plan(pl[:steps], :user => @current_user, :role => @current_role)
      render :json => { :ok => true, :mode => 'result', :steps => pl[:steps], :results => results }
    end
  rescue => e
    render :json => { :ok => false, :error => e.message }, :status => 500
  end

  # POST /ai_agent/run_plan  { steps } - execute an APPROVED multi-step plan (JSON array).
  def run_plan
    return deny unless @current_user
    steps = params[:steps]
    steps = (JSON.parse(steps) rescue nil) if steps.is_a?(String)
    return render(:json => { :ok => false, :error => 'ไม่มีแผน' }, :status => 400) unless steps.is_a?(Array) && steps.any?

    # Guard: every tool must exist; danger tools are developer-only.
    steps.each do |s|
      t = Ai::Tools.find((s['tool'] || s[:tool]).to_s)
      return render(:json => { :ok => false, :error => "unknown tool: #{s['tool']}" }, :status => 400) unless t
      if t[:risk] == :write_danger && @current_role.to_s != 'developer'
        return render(:json => { :ok => false, :error => "tool #{t[:name]} ต้องเป็น developer" }, :status => 403)
      end
    end

    results = Ai::Agent.execute_plan(steps, :user => @current_user, :role => @current_role)
    Ai::Provider.log("[AI-AGENT] run_plan steps=#{steps.size} user=#{@current_user.id}")
    render :json => { :ok => true, :results => results }
  rescue ActiveRecord::RecordNotFound
    render :json => { :ok => false, :error => 'ไม่พบข้อมูล' }, :status => 404
  rescue => e
    render :json => { :ok => false, :error => e.message }, :status => 500
  end

  # POST /ai_agent/execute  { tool, args } - run an APPROVED write tool. Args = the resolved
  # spec from the proposal. ACL is enforced inside each tool; danger tools are developer-only.
  def execute
    return deny unless @current_user
    tool = Ai::Tools.find(params[:tool])
    return render(:json => { :ok => false, :error => 'unknown tool' }, :status => 404) unless tool
    return render(:json => { :ok => false, :error => 'read tool ไม่ต้อง execute' }, :status => 400) if tool[:risk] == :read
    if tool[:risk] == :write_danger && @current_role.to_s != 'developer'
      return render(:json => { :ok => false, :error => 'ต้องเป็น developer' }, :status => 403)
    end
    result = Ai::Tools.run(params[:tool], args_hash, :user => @current_user, :role => @current_role)
    Ai::Provider.log("[AI-AGENT] execute tool=#{tool[:name]} user=#{@current_user.id}")
    render :json => { :ok => true, :tool => tool[:name], :result => result }
  rescue ActiveRecord::RecordNotFound
    render :json => { :ok => false, :error => 'ไม่พบข้อมูล' }, :status => 404
  rescue => e
    render :json => { :ok => false, :error => e.message }, :status => 500
  end

  private

  def deny
    render :json => { :ok => false, :error => 'กรุณาเข้าสู่ระบบ' }, :status => 401
  end

  # params[:args] -> plain Hash with string keys. Accepts a Hash or a JSON string.
  def args_hash
    a = params[:args]
    return {} unless a
    a = (JSON.parse(a) rescue {}) if a.is_a?(String)
    a = a.to_unsafe_h if a.respond_to?(:to_unsafe_h)
    return {} unless a.is_a?(Hash)
    Hash[a.map { |k, v| [k.to_s, v] }]
  end
end
