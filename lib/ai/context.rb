# Ai::Context - safe, allowlisted access to repository files for the AI Assistant modes.
#
# Security model: the UI only offers paths from a server-computed allowlist, and the
# backend reads a path ONLY if it is a member of that same allowlist (set membership,
# not path arithmetic on user input). Reads are additionally confined to the repo root
# via realpath and size-capped. Secret files (config/initializers/esm.rb, database.yml,
# config/ssl/, secret_token) are never in the allowlist, so they can never be read here.
module Ai
  module Context
    MAX_FILE_BYTES = 20_000

    # Curated allowlist globs, relative to Rails.root. Add dirs here to widen scope.
    DOC_GLOBS  = ['doc/understanding/*.md'].freeze
    CODE_GLOBS = [
      'app/models/**/*.rb',
      'app/controllers/*.rb',
      'app/helpers/*.rb',
      'lib/ai/*.rb',
      'config/routes.rb',
      'db/schema.rb'
    ].freeze

    module_function

    def root
      Rails.root.to_s
    end

    # doc/understanding/*.md  (Project & Documentation modes)
    def project_files
      glob_rel(DOC_GLOBS)
    end

    # curated source files  (Code & Agent modes)
    def code_files
      glob_rel(CODE_GLOBS)
    end

    def allowed
      (project_files + code_files).uniq
    end

    def allowed?(rel)
      allowed.include?(rel.to_s)
    end

    # Returns file content (String) or nil. Enforces allowlist + repo-root + size cap.
    def read(rel)
      rel = rel.to_s
      return nil unless allowed?(rel)

      abs = File.expand_path(File.join(root, rel))
      return nil unless abs.start_with?(root + File::SEPARATOR)
      return nil unless File.file?(abs)

      # Defense in depth: reject symlinks that escape the repo root.
      real = (File.realpath(abs) rescue nil)
      return nil unless real && real.start_with?(File.realpath(root) + File::SEPARATOR)

      data = File.read(abs)
      if data.bytesize > MAX_FILE_BYTES
        data = data.byteslice(0, MAX_FILE_BYTES).to_s
        data << "\n... [truncated at #{MAX_FILE_BYTES} bytes] ..."
      end
      data
    rescue
      nil
    end

    def glob_rel(globs)
      base   = root
      prefix = base + File::SEPARATOR
      Array(globs).flat_map { |g| Dir.glob(File.join(base, g)) }
                  .select  { |p| File.file?(p) }
                  .map     { |p| p.sub(/\A#{Regexp.escape(prefix)}/, '') }
                  .uniq.sort
    end
  end
end
