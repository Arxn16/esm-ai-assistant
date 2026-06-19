# Ai::FormBuilder - turns a clinician's natural-language request into ONE safe, additive
# form-field suggestion, and is the SINGLE validation choke point for any field spec before
# it can be applied to a Document/Table.
#
# SECURITY (critical): a field's column_name is later interpolated into Table.data, which
# Schema#load_model eval's at runtime. So column_name MUST pass a strict allowlist regex here,
# and field_type MUST be in ALLOWED_FIELD_TYPES. Both the AI path (#suggest) and the
# controller's #apply re-validation go through #validate. NEVER trust client input.
#
# Ruby 2.3 / Rails 4.2 compatible. No external gems (uses the existing Ai::Provider + JSON).
module Ai
  module FormBuilder

    # snake_case ascii, starts with a letter, <= 63 chars. This closes the eval-injection
    # vector that exists because Table#add_column does raw string interpolation of the name.
    NAME_RE = /\A[a-z][a-z0-9_]{0,62}\z/

    # Additive, data-bearing field types ONLY. Each maps to a non-nil column in
    # Document.data_types, so applying one creates a real Mongo column. Visual/relation/image/
    # map/extra/grid types are intentionally excluded - they need extra config and are riskier.
    ALLOWED_FIELD_TYPES = %w{
      text_string text_area text_integer text_float
      select_string select_integer select_date select_time select_datetime
      radio_string radio_integer check_string check_integer
    }.freeze

    # Choice types REQUIRE a list of options (LOV). Without options the runtime renders
    # "Not available." instead of a usable input - so we demand options for these.
    CHOICE_TYPES = %w{
      select_string select_integer radio_string radio_integer check_string check_integer
    }.freeze

    # field_type -> short human label shown in the suggestion card ("Add field: x (textarea)").
    UI_LABELS = {
      'text_string'     => 'text',     'text_area'    => 'textarea',
      'text_integer'    => 'number',   'text_float'   => 'decimal',
      'select_string'   => 'select',   'select_integer' => 'select',
      'select_date'     => 'date',     'select_time'  => 'time', 'select_datetime' => 'datetime',
      'radio_string'    => 'radio',    'radio_integer' => 'radio',
      'check_string'    => 'checkbox', 'check_integer' => 'checkbox'
    }.freeze

    # qwen3:8b gives more reliable JSON than 1.7b; override with AI_FORM_MODEL.
    MODEL = (ENV['AI_FORM_MODEL'] || 'qwen3:8b').freeze

    module_function

    def system_prompt
      'You convert ONE clinician request into ONE form field definition for a medical form ' \
      'builder. Reply with a SINGLE JSON object ONLY - no prose, no markdown fences. Keys: ' \
      '"column_name" (snake_case English identifier: lowercase a-z, 0-9, underscore; must start ' \
      'with a letter; <= 63 chars; derived from the field meaning), ' \
      '"field_type" (exactly one of: ' + ALLOWED_FIELD_TYPES.join(', ') + '), ' \
      '"label" (a short human label, may be in the user\'s language). ' \
      'Type mapping hints: short free text=text_string; long text / notes / history=text_area; ' \
      'whole number=text_integer; decimal=text_float; choose one from a list=select_string; ' \
      'date=select_date; time=select_time; date and time=select_datetime; single choice ' \
      'buttons=radio_string; multiple checkboxes=check_string. ' \
      'When field_type is a choice type (select_string, select_integer, radio_string, ' \
      'radio_integer, check_string, check_integer) you MUST ALSO include "options": an array ' \
      'of 2-8 short choice strings appropriate to the field, in the user\'s language ' \
      '(e.g. religion -> ["Buddhist","Christian","Muslim","Hindu","Other"]). For non-choice ' \
      'types, omit "options". ' \
      'If the request is NOT about adding a field, return {"field_type":"none"}.'
    end

    # Natural language -> validated suggestion.
    # Returns {:ok=>true, :suggestion=>{...}} or {:ok=>false, :error=>"..."}.
    def suggest(prompt, document, engine = 'ollama', model = nil)
      # Force UTF-8 (clinicians type Thai/other scripts; JSON.generate rejects ASCII-8BIT bytes).
      text = prompt.to_s.dup.force_encoding('UTF-8')
      text = text.scrub('') if text.respond_to?(:scrub)
      text = text.strip
      return err('กรุณาพิมพ์คำสั่ง เช่น "เพิ่มช่องประวัติการสูบบุหรี่ แบบข้อความยาว"') if text == ''

      messages = [
        { :role => 'system', :content => system_prompt },
        { :role => 'user',   :content => text[0, 1000] }
      ]
      opts = {
        :mode    => 'form_builder',
        :format  => 'json',
        :model   => (model.to_s.strip == '' ? MODEL : model.to_s.strip),
        :options => { :num_ctx => 2048, :num_predict => 200 }
      }

      reply = Ai::Provider.for(engine).chat(messages, opts)
      data  = parse_json(reply[:content].to_s)
      unless data.is_a?(Hash)
        return err('AI ตอบไม่เป็นรูปแบบที่อ่านได้ ลองพิมพ์ใหม่ให้ชัดขึ้น')
      end
      validate(data, document, text)
    end

    # The single validation choke point. Used by #suggest (AI output) AND the controller's
    # #apply (client-submitted spec). Returns the same {:ok=>...} shape.
    def validate(data, document, prompt = nil)
      col = data['column_name'].to_s.strip.downcase
      ft  = data['field_type'].to_s.strip
      lbl = data['label'].to_s.strip

      return err('คำสั่งนี้ไม่ใช่การเพิ่มฟิลด์ ลองพิมพ์ใหม่') if ft == 'none' || ft == ''
      return err('ชื่อคอลัมน์ไม่ถูกต้อง: ต้องเป็น a-z, 0-9, _ และขึ้นต้นด้วยตัวอักษร') unless col =~ NAME_RE
      return err('ชนิดฟิลด์ไม่อนุญาต: ' + ft) unless ALLOWED_FIELD_TYPES.include?(ft)
      lbl = col.tr('_', ' ').capitalize if lbl == ''

      # Choice types need a list of options (LOV); sanitize and require >= 2.
      options = []
      if CHOICE_TYPES.include?(ft)
        raw = data['options'].is_a?(Array) ? data['options'] : []
        options = raw.map { |o| o.to_s.dup.force_encoding('UTF-8').gsub(/[\r\n|]/, ' ').strip }
                     .reject { |o| o == '' }.uniq.first(20)
        if options.size < 2
          return err('ฟิลด์แบบตัวเลือก (dropdown/radio/checkbox) ต้องมีตัวเลือกอย่างน้อย 2 รายการ — ลองระบุตัวเลือกในคำสั่ง')
        end
      end

      if document
        existing = (Array(document.fields).map { |f| f.column_name.to_s } rescue [])
        return err('มีคอลัมน์ "' + col + '" ในฟอร์มแล้ว') if existing.include?(col)
        if document.table && document.table.data_columns.key?(col)
          return err('มีคอลัมน์ "' + col + '" ในตารางแล้ว')
        end
      end

      { :ok => true, :suggestion => {
        'action'      => 'add_field',
        'column_name' => col,
        'field_type'  => ft,
        'label'       => lbl,
        'ui_type'     => (UI_LABELS[ft] || ft),
        'options'     => options,
        'prompt'      => prompt.to_s
      } }
    end

    def err(msg)
      { :ok => false, :error => msg }
    end

    # Tolerant JSON parse: try the whole string, else the first balanced {...} block.
    def parse_json(raw)
      s = raw.to_s.strip
      obj = (JSON.parse(s) rescue nil)
      return obj if obj.is_a?(Hash)
      if s =~ /\{.*\}/m
        obj = (JSON.parse(s[/\{.*\}/m]) rescue nil)
        return obj if obj.is_a?(Hash)
      end
      nil
    end

  end
end
