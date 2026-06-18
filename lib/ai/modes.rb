# Ai::Modes - registry of AI Assistant modes. Each mode defines its system prompt,
# what file context it may inject (:none / :docs / :code), and provider options
# (:num_ctx, :num_predict). Modes are server-defined only; the client sends only a mode KEY.
#
# Application-agnostic by design: ESM hosts many apps (EMR, PACS, LIS, Inventory, ERP, ...).
# Prompts must NOT assume a domain, and treat real records as out of scope (definitions-only).
module Ai
  module Modes
    PREAMBLE = "You are an engineering assistant for the ESM platform, a metadata-driven system " \
               "that HOSTS MANY APPLICATIONS (for example EMR, PACS, LIS, Inventory, ERP, and others). " \
               "Stay application-agnostic: do NOT assume a healthcare or any specific business domain " \
               "unless the provided project metadata or files explicitly indicate it. Reason ONLY about " \
               "architecture, code, and DEFINITIONS (projects, services, operations, tables, fields, menus, " \
               "routes, controllers, documentation). NEVER assume, request, or invent the contents of real " \
               "records (patients, inventory, orders, attachments, GridFS, etc.) - those are out of scope. " \
               "BE CONCISE: prefer bullet points, avoid unnecessary explanation, and keep answers short " \
               "unless the user explicitly asks for more detail.".freeze

    CONTRACT = "Operate under the project operating contract: FIRST explain Understanding, Root Cause, " \
               "Proposed Solution, Files To Modify, Risks, and Database Impact. Do NOT write or apply code, " \
               "do NOT run commands, and never claim you changed anything. Preserve Ruby 2.3 / Rails 4.2 " \
               "compatibility and the existing style. Keep each section brief (bullet points). End by waiting for approval.".freeze

    DEFINITIONS = {
      'chat' => {
        :label => 'Chat', :context => :none, :num_ctx => nil, :num_predict => 80,
        :system => "#{PREAMBLE}\n\nAnswer general engineering questions. If you are unsure, say so."
      },
      'project' => {
        :label => 'Project', :context => :docs, :num_ctx => 4096, :num_predict => 120,
        :system => "#{PREAMBLE}\n\nUsing the selected project's metadata and any provided documentation, explain THIS " \
                   "application's architecture, request flow (services -> operations), data model (tables/fields), and " \
                   "navigation (menus). Cite sources. If something is not in the provided context, say so plainly."
      },
      'code' => {
        :label => 'Code', :context => :code, :num_ctx => 4096, :num_predict => 150,
        :system => "#{PREAMBLE}\n\nUse ONLY the provided source file(s) to explain code, suggest implementations, or " \
                   "suggest fixes. Cite file:line. Show suggested code as snippets, but do NOT claim to have applied " \
                   "anything. Keep Ruby 2.3 / Rails 4.2 compatibility and the existing coding style."
      },
      'agent' => {
        :label => 'Agent', :context => :code, :num_ctx => 4096, :num_predict => 250,
        :system => "#{PREAMBLE}\n\n#{CONTRACT}"
      },
      'documentation' => {
        :label => 'Documentation', :context => :docs, :num_ctx => 4096, :num_predict => 250,
        :system => "#{PREAMBLE}\n\nOutput GitHub-flavored markdown ONLY. Use the provided context; cite sources; flag " \
                   "anything you cannot verify. Do not write files - output the markdown for the user to save."
      }
    }.freeze

    DEFAULT = 'chat'.freeze

    module_function

    def get(name)
      DEFINITIONS[name.to_s] || DEFINITIONS[DEFAULT]
    end

    def valid?(name)
      DEFINITIONS.key?(name.to_s)
    end

    def keys
      DEFINITIONS.keys
    end
  end
end
