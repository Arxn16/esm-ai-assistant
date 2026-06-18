# Ai::ProjectContext - DEFINITIONS-ONLY metadata summary of an ESM hosted application
# (a Project), for the AI Assistant. Application-agnostic: works for EMR/PACS/LIS/ERP/etc.
#
# STRICT BOUNDARY (project-aware, NOT record-aware):
#   Reads ONLY MySQL metadata via ActiveRecord associations -
#   esm_projects / esm_services / esm_operations / esm_schemas / esm_tables /
#   menu_actions / esm_documents (the DEFINITION rows).
#   It NEVER touches MongoDB records, GridFS, attachments, or any real business/patient
#   data, and never calls load_model / get_model. Definitions in, never records.
module Ai
  module ProjectContext
    MAX_SERVICES = 40
    MAX_OPS      = 30
    MAX_TABLES   = 40
    MAX_COLS     = 40
    MAX_MENUS    = 40
    MAX_DOCS     = 40
    MAX_BYTES    = 16_000

    module_function

    # [[id, "solution / label"], ...] for the Project picker, scoped to the user's solution.
    def options_for(user, solution = nil)
      return [] unless user
      scope_projects(user, solution).map { |p| [p.id, label_for(p)] }
    rescue
      []
    end

    # ACL check: the project must belong to one of the user's accessible solutions.
    def accessible?(user, project_id)
      return false unless user && project_id.to_s != ''
      scope_projects(user, nil, true).any? { |p| p.id.to_s == project_id.to_s }
    rescue
      false
    end

    # Definitions-only structural summary (String), or nil if not accessible.
    def summary(user, project_id)
      return nil unless accessible?(user, project_id)
      p = (Project.find_by_id(project_id) rescue nil)
      return nil unless p

      out = []
      out << "PROJECT: #{p.name}"
      out << "TITLE: #{p.title}" if p.respond_to?(:title) && p.title.to_s != ''
      out << "PACKAGE: #{p.package}" if p.respond_to?(:package)
      out << "SOLUTION: #{((p.esm && p.esm.name) rescue '')}"
      out << "EXTENDS: #{p.extended}" if p.respond_to?(:extended) && p.extended.to_s != ''
      out << "(Definitions only - no real records are included.)"

      # Services -> Operations  (the application's request flow / "routes")
      services = (p.services.to_a rescue [])
      out << "\nSERVICES (service -> operations):"
      services.first(MAX_SERVICES).each do |s|
        names = (s.operations.to_a.map { |o| o.name }.compact rescue [])
        more  = names.size > MAX_OPS ? ", ... (+#{names.size - MAX_OPS})" : ""
        out << "  - #{s.name}: #{names.first(MAX_OPS).join(', ')}#{more}"
      end
      out << "  ... (+#{services.size - MAX_SERVICES} more services)" if services.size > MAX_SERVICES

      # Tables -> columns  (the data model; columns parsed from the `key :col` definitions)
      tables = project_tables(p)
      if tables.any?
        out << "\nTABLES (data model):"
        tables.first(MAX_TABLES).each do |t|
          cols = (t.data.to_s.scan(/key\s+:(\w+)/).flatten rescue [])
          out << "  - #{t.name}: #{cols.first(MAX_COLS).join(', ')}"
        end
        out << "  ... (+#{tables.size - MAX_TABLES} more tables)" if tables.size > MAX_TABLES
      end

      # Menus (navigation)
      menus = (p.menu_actions.to_a rescue [])
      if menus.any?
        out << "\nMENUS (navigation):"
        menus.first(MAX_MENUS).each { |m| out << "  - #{m.name} -> #{m.url}" }
      end

      # Forms / documents (names only - these are field DEFINITIONS, not records)
      docs = (p.documents.to_a rescue [])
      if docs.any?
        out << "\nFORMS/DOCUMENTS:"
        docs.first(MAX_DOCS).each do |d|
          t = (d.title.to_s != '' ? " (#{d.title})" : '')
          out << "  - #{d.name}#{t}"
        end
      end

      text = out.join("\n")
      text.bytesize > MAX_BYTES ? (text.byteslice(0, MAX_BYTES).to_s + "\n... [truncated] ...") : text
    rescue
      nil
    end

    # ---- helpers (all read MySQL metadata only) ----

    def scope_projects(user, solution = nil, all_solutions = false)
      if all_solutions
        sols = (user.my_solutions.to_a rescue [])
        return sols.flat_map { |s| (s.projects.to_a rescue []) }.uniq
      end
      sol = solution || (user.my_solutions.to_a.first rescue nil)
      return [] unless sol
      (sol.projects.to_a rescue [])
    end

    def project_tables(p)
      (p.respond_to?(:schema) && p.schema) ? (p.schema.tables.to_a rescue []) : []
    rescue
      []
    end

    def label_for(p)
      sol   = ((p.esm && p.esm.name) rescue nil)
      title = (p.respond_to?(:title) && p.title.to_s != '') ? p.title : p.name
      sol ? "#{sol} / #{title}" : title.to_s
    end
  end
end
