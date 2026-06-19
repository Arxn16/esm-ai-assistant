# Ai::Tools - the ESM agent's tool registry. The AI never touches the system directly; it
# CHOOSES a tool + fills args, and these validated tools do the work. This is the foundation
# for "an AI for all of ESM": add a tool here and the agent can use it.
#
# Each tool has a risk level that controls how it may run:
#   :read           - safe, no writes -> may run automatically
#   :write_additive - creates/adds only -> requires human approval
#   :write_danger   - destructive or evals code -> developer-only + review (not auto)
#
# Ruby 2.3 / Rails 4.2 compatible. Read tools must stay side-effect-free (no DB writes).
module Ai
  module Tools

    REGISTRY = {} unless defined?(REGISTRY)

    module_function

    def register(name, description, params, risk, &block)
      REGISTRY[name.to_s] = {
        :name => name.to_s, :description => description,
        :params => params, :risk => risk, :run => block
      }
    end

    # Public metadata (no :run proc) - safe to expose to the UI / send to the model.
    def catalog
      REGISTRY.values.map { |t| { :name => t[:name], :description => t[:description], :params => t[:params], :risk => t[:risk] } }
    end

    def find(name)
      REGISTRY[name.to_s]
    end

    def read_only?(name)
      t = find(name)
      t && t[:risk] == :read
    end

    # ctx carries :user, :role, and :dry_run. Write tools honor :dry_run (return a preview,
    # write nothing). Read-tool blocks take |a| and simply ignore the extra ctx arg.
    def run(name, args = {}, ctx = {})
      t = find(name)
      raise "unknown tool: #{name}" unless t
      t[:run].call(args || {}, ctx || {})
    end

    # =========================== READ TOOLS (safe, no writes) ===========================

    register('project_structure',
             'List a project: its services, tables, documents (with ids), and menus.',
             { 'project_id' => 'integer' }, :read) do |a|
      p = Project.find(a['project_id'])
      {
        :project   => p.name,
        :services  => (p.services.map(&:name) rescue []),
        :tables    => (p.documents.map { |d| d.table && d.table.name }.compact.uniq rescue []),
        :documents => p.documents.map { |d| { :id => d.id, :name => d.name, :title => d.title, :ai_editable => d.ai_editable } },
        :menus     => (p.menu_actions.map(&:name) rescue [])
      }
    end

    register('describe_document',
             'Show one document and all its fields (column_name, field_type, label).',
             { 'document_id' => 'integer' }, :read) do |a|
      d = Document.find(a['document_id'])
      {
        :id => d.id, :name => d.name, :title => d.title, :ai_editable => d.ai_editable,
        :fields => Array(d.fields).map { |f| { :column_name => f.column_name, :field_type => f.field_type, :label => f.label } }
      }
    end

    register('search_metadata',
             'Find documents and fields in a project whose name/label matches a keyword.',
             { 'project_id' => 'integer', 'keyword' => 'string' }, :read) do |a|
      p  = Project.find(a['project_id'])
      kw = a['keyword'].to_s.downcase
      docs   = p.documents.select { |d| d.name.to_s.downcase.include?(kw) || d.title.to_s.downcase.include?(kw) }
      fields = []
      p.documents.each do |d|
        Array(d.fields).each do |f|
          if f.column_name.to_s.downcase.include?(kw) || f.label.to_s.downcase.include?(kw)
            fields << { :document => d.name, :column => f.column_name, :type => f.field_type }
          end
        end
      end
      { :documents => docs.map { |d| { :id => d.id, :name => d.name } }, :fields => fields.first(30) }
    end

    register('list_projects',
             'List projects across the platform (id, name, solution).',
             {}, :read) do |a|
      Project.limit(150).map { |p| { :id => p.id, :name => p.name, :solution => (p.esm ? p.esm.name : nil) } }
    end

    register('find_document',
             'Find documents anywhere by a name/title keyword (returns ids + project).',
             { 'keyword' => 'string' }, :read) do |a|
      kw = "%#{a['keyword']}%"
      Document.where('name LIKE ? OR title LIKE ?', kw, kw).limit(15).map do |d|
        { :id => d.id, :name => d.name, :title => d.title, :project_id => d.project_id }
      end
    end

    register('get_service',
             'Show a service and the names of its operations (its controller-like logic).',
             { 'service_id' => 'integer' }, :read) do |a|
      s = Service.find(a['service_id'])
      { :id => s.id, :name => s.name, :extended => s.extended, :operations => (s.operations.map(&:name) rescue []) }
    end

    register('read_architecture_doc',
             'List ESM architecture docs in doc/understanding/, or read one by file name.',
             { 'file' => 'string (optional - omit to list)' }, :read) do |a|
      dir = Rails.root.join('doc', 'understanding')
      if a['file'].to_s.strip == ''
        { :files => (Dir.entries(dir.to_s).select { |f| f =~ /\.md\z/ }.sort rescue []) }
      else
        name = File.basename(a['file'].to_s) # strip any path traversal
        path = dir.join(name).to_s
        raise 'doc not found' unless name =~ /\.md\z/ && File.file?(path)
        { :file => name, :content => File.read(path)[0, 8000] }
      end
    end

    # =========================== WRITE TOOLS (need approval) ===========================
    # These honor ctx[:dry_run] => return a preview (resolved spec) WITHOUT writing.

    register('add_field',
             'Add a field to a document from a natural-language description (additive only). ' \
             'Args: document_id, request (the field to add, e.g. "ประวัติแพ้ยา แบบข้อความยาว").',
             { 'document_id' => 'integer', 'request' => 'string' }, :write_additive) do |a, ctx|
      doc = Document.find(a['document_id'])
      unless ctx[:role].to_s == 'developer' || doc.ai_editable
        raise 'ฟอร์มนี้ยังไม่เปิดให้แก้ผ่าน AI (ai_editable=false)'
      end

      # Resolve the concrete spec: re-execute of an approved proposal supplies column_name+
      # field_type (validate them); a fresh request is turned into a spec via FormBuilder.
      if a['column_name'].to_s != '' && a['field_type'].to_s != ''
        v = Ai::FormBuilder.validate({ 'column_name' => a['column_name'], 'field_type' => a['field_type'],
                                       'label' => a['label'], 'options' => a['options'] }, doc)
      else
        v = Ai::FormBuilder.suggest(a['request'].to_s, doc)
      end
      raise v[:error] unless v[:ok]
      s = v[:suggestion]

      if ctx[:dry_run]
        opts_txt = (s['options'].to_a.any? ? " ตัวเลือก: #{s['options'].join(', ')}" : '')
        next({
          :preview  => true,
          :summary  => "เพิ่มฟิลด์ #{s['column_name']} (#{s['ui_type']})#{opts_txt} ลงฟอร์ม #{doc.name}",
          :resolved => { 'document_id' => doc.id, 'column_name' => s['column_name'],
                         'field_type' => s['field_type'], 'label' => s['label'], 'options' => s['options'] }
        })
      end

      raise 'ฟอร์มนี้ไม่มี table ปลายทาง' unless doc.table
      if ctx[:user]
        EsmDocumentVersion.create(:document_id => doc.id, :table_id => doc.table_id,
          :data => doc.data, :tree_data => doc.tree_data, :table_data => (doc.table && doc.table.data),
          :author_id => ctx[:user].id, :author_name => ((ctx[:user].name rescue nil) || ctx[:user].id.to_s),
          :source => 'agent', :note => s.to_json)
      end
      fp = { 'name' => s['label'], 'label' => s['label'], 'column_name' => s['column_name'],
             'field_type' => s['field_type'], 'list_show' => '1' }
      if s['options'].is_a?(Array) && !s['options'].empty?
        fp['lov_type'] = 'plain'
        fp['lov']      = s['options'].join("\n")
      end
      f = doc.add_field(fp.with_indifferent_access)
      { :created => 'field', :document_id => doc.id, :column_name => s['column_name'],
        :field_type => s['field_type'], :field_id => f.id }
    end

    register('create_document',
             'Create a new form (Document + Table) in a project (additive). Developer only. ' \
             'Args: project_id, name (snake_case), title (optional).',
             { 'project_id' => 'integer', 'name' => 'string', 'title' => 'string (optional)' }, :write_additive) do |a, ctx|
      proj = Project.find(a['project_id'])
      raise 'สร้างฟอร์มต้องเป็น developer' unless ctx[:role].to_s == 'developer'
      name = a['name'].to_s.strip.downcase.gsub(/[^a-z0-9_]/, '_').gsub(/_+/, '_').gsub(/\A_+|_+\z/, '')
      raise 'ชื่อฟอร์มไม่ถูกต้อง (ต้อง a-z, 0-9, _ ขึ้นต้นด้วยตัวอักษร)' unless name =~ /\A[a-z][a-z0-9_]*\z/
      raise "มีฟอร์มชื่อ '#{name}' อยู่แล้วในโปรเจกต์นี้" if proj.documents.where(:name => name).exists?
      title = a['title'].to_s.strip
      title = name.tr('_', ' ').capitalize if title == ''

      if ctx[:dry_run]
        next({ :preview => true,
               :summary => "สร้างฟอร์มใหม่ '#{title}' (name=#{name}) ในโปรเจกต์ #{proj.name}",
               :resolved => { 'project_id' => proj.id, 'name' => name, 'title' => title } })
      end

      table = proj.get_schema.tables.find_or_create_by(:name => name)
      doc = proj.documents.new
      doc.name = name; doc.title = title; doc.table_id = table.id; doc.ai_editable = true
      doc.save
      { :created => 'document', :document_id => doc.id, :name => doc.name, :title => doc.title,
        :ai_editable => true,
        :note => 'สร้างฟอร์มแล้ว (เพิ่มฟิลด์ผ่าน AI ได้เลย). ยังไม่มี service/menu - ต้อง publish เพื่อเป็นหน้า runtime' }
    end

    register('hide_field',
             'Remove a field from a form - DATA-SAFE & reversible: the column and its records ' \
             'stay; rollback restores it. Args: document_id, column_name.',
             { 'document_id' => 'integer', 'column_name' => 'string' }, :write_additive) do |a, ctx|
      doc = Document.find(a['document_id'])
      unless ctx[:role].to_s == 'developer' || doc.ai_editable
        raise 'ฟอร์มนี้ยังไม่เปิดให้แก้ผ่าน AI (ai_editable=false)'
      end
      col   = a['column_name'].to_s.strip
      field = doc.find_by_column_name(col)
      raise "ไม่พบฟิลด์ '#{col}' ในฟอร์มนี้" unless field

      if ctx[:dry_run]
        next({ :preview => true,
               :summary => "เอาฟิลด์ '#{col}' ออกจากฟอร์ม #{doc.name} (คอลัมน์+ข้อมูลคงไว้ กู้คืนได้)",
               :resolved => { 'document_id' => doc.id, 'column_name' => col } })
      end

      if ctx[:user]
        EsmDocumentVersion.create(:document_id => doc.id, :table_id => doc.table_id,
          :data => doc.data, :tree_data => doc.tree_data, :table_data => (doc.table && doc.table.data),
          :author_id => ctx[:user].id, :author_name => ((ctx[:user].name rescue nil) || ctx[:user].id.to_s),
          :source => 'agent', :note => "hide_field #{col}")
      end
      doc.fields.delete(field)
      doc.save
      { :removed => 'field_from_form', :document_id => doc.id, :column_name => col,
        :note => 'คอลัมน์และข้อมูลใน DB ยังอยู่ - กู้คืนได้ด้วย rollback เวอร์ชัน' }
    end

    register('publish_document',
             'Publish a form: create its Service + Menu so it becomes a live runtime page ' \
             '(/.../<Name>/index, .../create). Developer only. Args: document_id.',
             { 'document_id' => 'integer' }, :write_additive) do |a, ctx|
      raise 'publish ต้องเป็น developer' unless ctx[:role].to_s == 'developer'
      doc  = Document.find(a['document_id'])
      if doc.service_id && Service.where(:id => doc.service_id).exists?
        raise "ฟอร์ม '#{doc.name}' publish ไว้แล้ว (มี service)"
      end
      proj = doc.project
      url  = "../#{doc.name.classify}/index"

      if ctx[:dry_run]
        next({ :preview => true,
               :summary => "publish ฟอร์ม '#{doc.name}': สร้าง Service + Menu (เข้าได้ที่ #{url}, /create)",
               :resolved => { 'document_id' => doc.id } })
      end

      tmpl = ScriptTemplate.find_by_name('ServiceTemplate')
      raise 'ไม่พบ ScriptTemplate "ServiceTemplate"' unless tmpl
      # Same recipe the app uses when a developer creates a Document (see EsmDocumentsController#new).
      service = proj.services.create(:name => doc.name.downcase.split.join('_'),
                                     :title => doc.title, :extended => 'system.util.Document')
      proj.menu_actions.create(:name => doc.title, :url => url)
      op = service.operations.build(:name => 'document_name',
                                    :command => "'#{doc.name}'", :template_id => tmpl.id)
      op.save
      doc.service = service
      doc.save
      { :published => true, :document_id => doc.id, :service_id => service.id, :menu_url => url }
    end

    register('create_project',
             'Create a new project under a solution (developer only). ' \
             'Args: solution (esm name), name (snake_case), description (optional).',
             { 'solution' => 'string', 'name' => 'string', 'description' => 'string (optional)' }, :write_danger) do |a, ctx|
      raise 'create_project ต้องเป็น developer' unless ctx[:role].to_s == 'developer'
      esm = Esm.find_by_name(a['solution'].to_s) || (Esm.where(:id => a['solution']).first)
      raise "ไม่พบ solution '#{a['solution']}'" unless esm
      name = a['name'].to_s.strip.downcase.gsub(/[^a-z0-9_]/, '_').gsub(/_+/, '_').gsub(/\A_+|_+\z/, '')
      raise 'ชื่อ project ไม่ถูกต้อง (a-z, 0-9, _ ขึ้นต้นด้วยตัวอักษร)' unless name =~ /\A[a-z][a-z0-9_]*\z/
      raise "มี project '#{name}' อยู่แล้วใน solution นี้" if esm.projects.where(:name => name).exists?
      pkg = "#{esm.name}.#{name}"

      if ctx[:dry_run]
        next({ :preview => true,
               :summary => "สร้าง project '#{name}' (package #{pkg}) ใน solution #{esm.name}",
               :resolved => { 'solution' => esm.name, 'name' => name, 'description' => a['description'].to_s } })
      end

      proj = esm.projects.new
      proj.name = name; proj.package = pkg; proj.description = a['description'].to_s
      proj.save
      { :created => 'project', :project_id => proj.id, :name => proj.name, :package => pkg }
    end

    register('create_menu',
             'Add a menu item to a project (developer only). Args: project_id, name (label), url.',
             { 'project_id' => 'integer', 'name' => 'string', 'url' => 'string' }, :write_additive) do |a, ctx|
      raise 'create_menu ต้องเป็น developer' unless ctx[:role].to_s == 'developer'
      proj = Project.find(a['project_id'])
      name = a['name'].to_s.strip
      url  = a['url'].to_s.strip
      raise 'ต้องมีชื่อเมนูและ url' if name == '' || url == ''

      if ctx[:dry_run]
        next({ :preview => true,
               :summary => "เพิ่มเมนู '#{name}' -> #{url} ในโปรเจกต์ #{proj.name}",
               :resolved => { 'project_id' => proj.id, 'name' => name, 'url' => url } })
      end

      m = proj.menu_actions.create(:name => name, :url => url)
      { :created => 'menu', :project_id => proj.id, :name => name, :url => url, :menu_id => (m.id rescue nil) }
    end

    register('list_versions',
             'List a document\'s version / undo history (newest first).',
             { 'document_id' => 'integer' }, :read) do |a|
      EsmDocumentVersion.where(:document_id => a['document_id']).order('id DESC').limit(20).map do |v|
        { :id => v.id, :source => v.source, :author => v.author_name,
          :at => (v.created_at ? v.created_at.strftime('%Y-%m-%d %H:%M') : ''),
          :note => v.note.to_s[0, 80] }
      end
    end

    register('rollback_document',
             'UNDO: restore a form to a previous version - data-safe (columns & records are kept). ' \
             'Args: document_id, version_id (optional = the latest snapshot = undo last change).',
             { 'document_id' => 'integer', 'version_id' => 'integer (optional)' }, :write_additive) do |a, ctx|
      doc = Document.find(a['document_id'])
      unless ctx[:role].to_s == 'developer' || doc.ai_editable
        raise 'ฟอร์มนี้ยังไม่เปิดให้แก้ผ่าน AI (ai_editable=false)'
      end
      # Capture target version BEFORE writing the new snapshot below.
      ver = if a['version_id'].to_s != ''
              EsmDocumentVersion.where(:document_id => doc.id).find(a['version_id'])
            else
              EsmDocumentVersion.where(:document_id => doc.id).order('id DESC').first
            end
      raise 'ไม่มีเวอร์ชันให้ย้อนกลับ' unless ver

      if ctx[:dry_run]
        next({ :preview => true,
               :summary => "ย้อนฟอร์ม #{doc.name} กลับไปเวอร์ชัน ##{ver.id} (#{ver.created_at}) - ข้อมูลไม่หาย",
               :resolved => { 'document_id' => doc.id, 'version_id' => ver.id } })
      end

      # Snapshot the current state first so the undo itself is reversible (redo).
      if ctx[:user]
        EsmDocumentVersion.create(:document_id => doc.id, :table_id => doc.table_id,
          :data => doc.data, :tree_data => doc.tree_data, :table_data => (doc.table && doc.table.data),
          :author_id => ctx[:user].id, :author_name => ((ctx[:user].name rescue nil) || ctx[:user].id.to_s),
          :source => 'rollback', :note => "before rollback to ##{ver.id}")
      end
      doc.data      = ver.data
      doc.tree_data = ver.tree_data
      doc.refresh_structure ver.data
      doc.save
      { :rolled_back => true, :document_id => doc.id, :to_version => ver.id,
        :note => 'ย้อนนิยามฟอร์มแล้ว (คอลัมน์+ข้อมูลใน DB คงไว้)' }
    end

  end
end
