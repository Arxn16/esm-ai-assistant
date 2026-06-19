# AI Form Builder - lets a clinician add a form field by chat: type -> AI suggestion ->
# human Apply/Reject -> versioned, additive change. The doctor never edits schema directly.
#
# SAFETY MODEL (production healthcare):
#   * Subclasses EsmController -> reuses the auth/session gate (@current_user / @current_role)
#     AND keeps CSRF protection ON (unlike EsmDocumentsController which skips it). The client
#     sends the X-CSRF-Token header.
#   * Every spec is RE-VALIDATED server-side through Ai::FormBuilder.validate before apply -
#     client input is never trusted (closes the eval-injection vector in Table#add_column).
#   * Additive only: this controller can ADD a field; it can never delete/rename/reorder.
#   * Versioned + audited: a snapshot is written BEFORE every change (who / when / prompt).
#   * Rollback restores the form definition only; table columns stay -> no record data lost.
class AiFormBuilderController < EsmController

  # Policy switch. false = any signed-in user (e.g. a doctor) may Apply (the whole point:
  # self-service for small additive changes). Set true to restrict Apply/Rollback to developers.
  APPLY_REQUIRES_DEVELOPER = false

  # GET /ai_form_builder/edit?document_id=X
  # Standalone clinician page (login only; role 'user' is fine - NOT behind the developer IDE gate).
  # The form must be opted-in (ai_editable) unless the caller is a developer.
  def edit
    return redirect_to('/user/login') unless @current_user
    @document = Document.find(params[:document_id])
    unless can_edit?(@document)
      return render(:text => 'ฟอร์มนี้ยังไม่เปิดให้แก้ผ่าน AI (ติดต่อผู้ดูแลระบบ/นักพัฒนา)', :status => 403)
    end
    render :layout => false
  rescue ActiveRecord::RecordNotFound
    render :text => 'ไม่พบฟอร์ม', :status => 404
  end

  # POST /ai_form_builder/suggest  { document_id, message }
  # -> { ok:true, suggestion:{action,column_name,field_type,label,ui_type,prompt} } | { ok:false, error }
  def suggest
    return deny unless @current_user
    doc    = Document.find(params[:document_id])
    return forbid_form unless can_edit?(doc)
    engine = (params[:engine].to_s.strip.downcase == 'cloud') ? 'cloud' : 'ollama'
    Ai::Provider.log("[AI-BUILDER] suggest doc=#{doc.id} user=#{@current_user.id}")
    render :json => Ai::FormBuilder.suggest(params[:message], doc, engine, params[:model])
  rescue ActiveRecord::RecordNotFound
    render :json => { :ok => false, :error => 'ไม่พบฟอร์ม' }, :status => 404
  rescue Ai::Error
    render :json => { :ok => false, :error => 'AI ไม่ตอบสนอง (timeout/unreachable) ลองใหม่อีกครั้ง' }, :status => 502
  rescue => e
    Ai::Provider.log("[AI-BUILDER] suggest error: #{e.class}: #{e.message}")
    render :json => { :ok => false, :error => 'เกิดข้อผิดพลาดภายใน' }, :status => 500
  end

  # POST /ai_form_builder/apply  { document_id, column_name, field_type, label, prompt }
  def apply
    return deny unless @current_user
    return forbid if APPLY_REQUIRES_DEVELOPER && @current_role.to_s != 'developer'

    doc = Document.find(params[:document_id])
    return forbid_form unless can_edit?(doc)

    # NEVER trust the client - re-validate the spec server-side.
    spec = { 'column_name' => params[:column_name], 'field_type' => params[:field_type],
             'label' => params[:label], 'options' => params[:options] }
    v = Ai::FormBuilder.validate(spec, doc, params[:prompt])
    return render(:json => v, :status => 422) unless v[:ok]

    s = v[:suggestion]
    return render(:json => { :ok => false, :error => 'ฟอร์มนี้ยังไม่มีตาราง (table) ปลายทาง เพิ่มฟิลด์ไม่ได้' }, :status => 422) unless doc.table

    version = snapshot(doc, 'ai', s)

    field_params = {
      'name'        => s['label'],
      'label'       => s['label'],
      'column_name' => s['column_name'],
      'field_type'  => s['field_type'],
      'list_show'   => '1'
    }
    # Choice types need a LOV, else the runtime renders "Not available." instead of an input.
    if s['options'].is_a?(Array) && !s['options'].empty?
      field_params['lov_type'] = 'plain'
      field_params['lov']      = s['options'].join("\n")
    end
    field = doc.add_field(field_params.with_indifferent_access)

    Ai::Provider.log("[AI-BUILDER] applied col=#{s['column_name']} type=#{s['field_type']} doc=#{doc.id} user=#{@current_user.id} ver=#{version.id}")
    render :json => {
      :ok          => true,
      :message     => "เพิ่มฟิลด์ \"#{s['column_name']}\" (#{s['ui_type']}) สำเร็จ",
      :field_id    => field.id,
      :column_name => s['column_name'],
      :version_id  => version.id
    }
  rescue ActiveRecord::RecordNotFound
    render :json => { :ok => false, :error => 'ไม่พบฟอร์ม' }, :status => 404
  rescue => e
    Ai::Provider.log("[AI-BUILDER] apply error: #{e.class}: #{e.message}")
    render :json => { :ok => false, :error => 'บันทึกไม่สำเร็จ: ' + e.message }, :status => 500
  end

  # GET /ai_form_builder/versions  { document_id }
  def versions
    return deny unless @current_user
    list = EsmDocumentVersion.where(:document_id => params[:document_id]).order('id DESC').limit(30)
    render :json => { :ok => true, :versions => list.map { |v|
      { :id => v.id, :source => v.source, :author => v.author_name,
        :note => v.note.to_s[0, 200],
        :at => (v.created_at ? v.created_at.strftime('%Y-%m-%d %H:%M') : '') }
    } }
  rescue => e
    render :json => { :ok => false, :versions => [] }
  end

  # POST /ai_form_builder/rollback  { document_id, version_id }
  # Safe rollback: restores the form definition only; additive table columns are left intact.
  def rollback
    return deny unless @current_user
    return forbid if APPLY_REQUIRES_DEVELOPER && @current_role.to_s != 'developer'

    doc = Document.find(params[:document_id])
    ver = EsmDocumentVersion.where(:document_id => doc.id).find(params[:version_id])

    snapshot(doc, 'rollback', nil, "rollback to ##{ver.id}")

    doc.data      = ver.data
    doc.tree_data = ver.tree_data
    doc.refresh_structure ver.data
    doc.save

    render :json => { :ok => true,
      :message => "ย้อนฟอร์มกลับไปเวอร์ชัน ##{ver.id} แล้ว (คอลัมน์ในตารางคงไว้ ไม่มีข้อมูลหาย)" }
  rescue ActiveRecord::RecordNotFound
    render :json => { :ok => false, :error => 'ไม่พบเวอร์ชัน' }, :status => 404
  rescue => e
    Ai::Provider.log("[AI-BUILDER] rollback error: #{e.class}: #{e.message}")
    render :json => { :ok => false, :error => 'ย้อนเวอร์ชันไม่สำเร็จ' }, :status => 500
  end

  private

  def deny
    render :json => { :ok => false, :error => 'กรุณาเข้าสู่ระบบ' }, :status => 401
  end

  def forbid
    render :json => { :ok => false, :error => 'สิทธิ์ไม่พอ (เฉพาะ developer)' }, :status => 403
  end

  def forbid_form
    render :json => { :ok => false, :error => 'ฟอร์มนี้ยังไม่เปิดให้แก้ผ่าน AI' }, :status => 403
  end

  # A clinician (role 'user') may edit only forms a developer opted-in (ai_editable).
  # Developers / admins (resolved to @current_role == 'developer') may edit any form.
  def can_edit?(doc)
    return true if @current_role.to_s == 'developer'
    !!doc.ai_editable
  end

  # Write an immutable snapshot of the document BEFORE a change. `suggestion` (if given) is
  # stored as JSON in note; otherwise `note` text is used.
  def snapshot(doc, source, suggestion, note = nil)
    author = (@current_user.name.presence || @current_user.email rescue nil) || @current_user.id.to_s
    EsmDocumentVersion.create(
      :document_id => doc.id,
      :table_id    => doc.table_id,
      :data        => doc.data,
      :tree_data   => doc.tree_data,
      :table_data  => (doc.table ? doc.table.data : nil),
      :author_id   => @current_user.id,
      :author_name => author,
      :source      => source,
      :note        => (suggestion ? suggestion.to_json : note.to_s)
    )
  end
end
