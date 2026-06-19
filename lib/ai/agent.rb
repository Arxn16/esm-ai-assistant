# Ai::Agent - the ESM agent loop (v1: single-step tool selection).
#
# Given a natural-language request, the AI picks ONE tool from Ai::Tools and fills its args
# (structured JSON). READ tools execute automatically; write tools are returned as a PROPOSAL
# for human approval (never auto-executed here). This keeps the dangerous capabilities gated.
#
# Ruby 2.3 / Rails 4.2 compatible.
module Ai
  module Agent

    # Local model used for PLANNING. Must be capable of structured JSON output. The tiny chat
    # model (qwen3:1.7b) returns prose/short text instead of a {"steps":[...]} array, which is the
    # #1 cause of "วางแผนไม่สำเร็จ". So on Local we always plan with this, ignoring the chat dropdown.
    PLAN_MODEL_LOCAL = (ENV['AI_PLAN_MODEL'] || 'qwen3:8b').freeze

    # Greetings / pleasantries: answered warmly instead of being forced through the planner
    # (which has nothing to plan and would error out).
    GREETINGS = %w[
      สวัสดี สวัสดีครับ สวัสดีค่ะ หวัดดี หวัดดีครับ หวัดดีค่ะ ดี ดีครับ ดีค่ะ ดีจ้า ทักทาย
      hi hello hey yo hallo ขอบคุณ ขอบคุณครับ ขอบคุณค่ะ thanks test ทดสอบ เทส เทสต์
    ].freeze

    module_function

    # True when the message is just a greeting/pleasantry, not an actionable command.
    def smalltalk?(text)
      s = text.to_s.dup.force_encoding('UTF-8')
      s = s.scrub('') if s.respond_to?(:scrub)
      s = s.strip.downcase
      return false if s == '' || s.length > 30
      return true if GREETINGS.include?(s)
      !!(s =~ /\A(สวัสดี|หวัดดี|hello|hi|hey)/)
    end

    # Friendly onboarding shown for greetings or when a request can't be turned into a plan.
    def intro_message
      "สวัสดีครับ ผมคือ ESM Agent — อ่าน สร้าง แก้ และ publish ฟอร์ม/โปรเจกต์ใน ESM ให้ได้ผ่านแชต\n\n" \
      "ลองสั่งแบบนี้:\n" \
      "- what projects exist\n" \
      "- describe document 132\n" \
      "- add a smoking history textarea to document 132\n" \
      "- in project 69 create a form cat with name + age, then publish\n\n" \
      "งานอ่าน = ตอบทันที / งานแก้ = เห็นแผนก่อน แล้วกด Apply"
    end

    def system_prompt
      lines = Ai::Tools.catalog.map do |t|
        keys = t[:params].keys.join(', ')
        "- #{t[:name]}(#{keys}) [#{t[:risk]}]: #{t[:description]}"
      end.join("\n")
      'You are an agent for the ESM platform. Pick exactly ONE tool to satisfy the request and ' \
      'fill its arguments from the request. Reply with a SINGLE JSON object only: ' \
      '{"tool": "<name>", "args": { ... }}. Use only a tool from this list; if none fits, ' \
      'reply {"tool":"none"}. Tools:' + "\n" + lines
    end

    # Returns:
    #   read tool  -> { ok:true, tool:, args:, result: }
    #   write tool -> { ok:true, proposal:true, tool:, args:, risk: }  (NOT executed)
    #   otherwise  -> { ok:false, error: }
    def route(text, opts = {})
      t = text.to_s.dup.force_encoding('UTF-8')
      t = t.scrub('') if t.respond_to?(:scrub)
      return { :ok => false, :error => 'empty request' } if t.strip == ''

      messages = [
        { :role => 'system', :content => system_prompt },
        { :role => 'user',   :content => t.strip[0, 1000] }
      ]
      engine = (opts[:engine].to_s == 'cloud') ? 'cloud' : 'ollama'
      chat_opts = {
        :mode    => 'agent_route',
        :format  => 'json',
        :model   => (opts[:model].to_s.strip == '' ? (Ai::FormBuilder::MODEL rescue nil) : opts[:model].to_s.strip),
        :options => { :num_ctx => 2048, :num_predict => 200 }
      }

      reply = Ai::Provider.for(engine).chat(messages, chat_opts)
      plan  = Ai::FormBuilder.parse_json(reply[:content].to_s)
      return { :ok => false, :error => 'AI ตอบไม่เป็น JSON ที่อ่านได้' } unless plan.is_a?(Hash)

      name = plan['tool'].to_s
      return { :ok => false, :error => 'ไม่พบเครื่องมือที่เหมาะกับคำขอ' } if name == '' || name == 'none'
      tool = Ai::Tools.find(name)
      return { :ok => false, :error => "unknown tool: #{name}" } unless tool

      args = plan['args'].is_a?(Hash) ? plan['args'] : {}

      if tool[:risk] == :read
        { :ok => true, :tool => name, :args => args, :result => Ai::Tools.run(name, args) }
      else
        # Write tool: preview only (dry_run) -> return a PROPOSAL with the resolved spec for
        # human approval. Never executed here. ACL/validation errors surface as a normal error.
        begin
          preview = Ai::Tools.run(name, args, { :dry_run => true, :user => opts[:user], :role => opts[:role] })
        rescue => e
          return { :ok => false, :error => e.message }
        end
        { :ok => true, :proposal => true, :tool => name, :risk => tool[:risk].to_s,
          :summary => (preview.is_a?(Hash) ? preview[:summary] : nil),
          :args => (preview.is_a?(Hash) && preview[:resolved] ? preview[:resolved] : args) }
      end
    rescue Ai::Error
      { :ok => false, :error => 'AI ไม่ตอบสนอง ลองใหม่' }
    rescue => e
      { :ok => false, :error => e.message }
    end

    # ---------------------------- MULTI-STEP (plan -> approve -> run) ----------------------------

    def plan_prompt
      lines = Ai::Tools.catalog.map do |t|
        "- #{t[:name]}(#{t[:params].keys.join(', ')}) [#{t[:risk]}]: #{t[:description]}"
      end.join("\n")
      'You are a planner for the ESM platform. Break the user request into an ORDERED list of ' \
      'tool calls. Reply with a SINGLE JSON object only: {"steps":[{"tool":"<name>","args":{...}}]}. ' \
      'Use ONLY tools from the list. When an argument depends on the OUTPUT of an earlier step, ' \
      'use a reference {"$ref":"<stepIndex>.<key>"} (0-based index), e.g. the new id from step 0: ' \
      '{"$ref":"0.document_id"}. Keep the plan minimal; do not invent ids. Tools:' + "\n" + lines
    end

    # NL -> ordered plan of tool calls (NOT executed). { ok, steps:[{tool,args,risk}], has_write }
    def plan(text, opts = {})
      t = text.to_s.dup.force_encoding('UTF-8')
      t = t.scrub('') if t.respond_to?(:scrub)
      return { :ok => false, :error => 'empty request' } if t.strip == ''

      engine = (opts[:engine].to_s == 'cloud') ? 'cloud' : 'ollama'
      model  = opts[:model].to_s.strip
      # Local planning ALWAYS uses a capable model (PLAN_MODEL_LOCAL); the 1.7b chat model can't
      # emit a steps array. Cloud: leave blank so the provider uses AI_CLOUD_MODEL.
      model  = PLAN_MODEL_LOCAL if engine == 'ollama'
      messages = [
        { :role => 'system', :content => plan_prompt },
        { :role => 'user',   :content => t.strip[0, 1500] }
      ]
      copts = { :mode => 'agent_plan', :format => 'json', :options => { :num_ctx => 4096, :num_predict => 600 } }
      copts[:model] = model unless model == ''

      reply = Ai::Provider.for(engine).chat(messages, copts)
      data  = Ai::FormBuilder.parse_json(reply[:content].to_s)
      raw   = (data.is_a?(Hash) ? data['steps'] : nil)
      return { :ok => false, :error => 'วางแผนไม่สำเร็จ (AI ตอบไม่เป็น steps)' } unless raw.is_a?(Array) && raw.any?

      steps = []
      raw.each do |s|
        next unless s.is_a?(Hash)
        name = s['tool'].to_s
        tool = Ai::Tools.find(name)
        return { :ok => false, :error => "unknown tool ในแผน: #{name}" } unless tool
        steps << { 'tool' => name, 'args' => (s['args'].is_a?(Hash) ? s['args'] : {}), 'risk' => tool[:risk].to_s }
      end
      return { :ok => false, :error => 'แผนว่าง' } if steps.empty?
      { :ok => true, :steps => steps, :has_write => steps.any? { |s| s['risk'] != 'read' } }
    rescue Ai::Error
      { :ok => false, :error => 'AI ไม่ตอบสนอง ลองใหม่' }
    rescue => e
      { :ok => false, :error => e.message }
    end

    # Run an APPROVED plan in order; resolve {"$ref":"i.key"} from earlier results. Returns results[].
    def execute_plan(steps, ctx = {})
      results = []
      Array(steps).each do |s|
        tool = (s['tool'] || s[:tool]).to_s
        args = resolve_refs((s['args'] || s[:args] || {}), results)
        results << Ai::Tools.run(tool, args, ctx)
      end
      results
    end

    def resolve_refs(args, results)
      out = {}
      (args || {}).each do |k, v|
        ref = v.is_a?(Hash) ? (v['$ref'] || v[:'$ref']) : nil
        if ref
          idx, key = ref.to_s.split('.', 2)
          r = results[idx.to_i]
          out[k.to_s] = (r.is_a?(Hash) ? (r[key] || r[key.to_s.to_sym]) : nil)
        else
          out[k.to_s] = v
        end
      end
      out
    end

  end
end
