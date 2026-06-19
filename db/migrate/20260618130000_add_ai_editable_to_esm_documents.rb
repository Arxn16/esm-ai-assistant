class AddAiEditableToEsmDocuments < ActiveRecord::Migration
  # Opt-in safety flag: a clinician (role 'user') may AI-edit a form ONLY when a developer has
  # turned this on for that specific form. Developers/admins bypass the flag.
  def change
    add_column :esm_documents, :ai_editable, :boolean, :default => false
  end
end
