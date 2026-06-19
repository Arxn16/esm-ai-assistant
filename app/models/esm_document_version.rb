# Immutable snapshot of a Document's definition, captured BEFORE every change (audit + rollback).
# Stores the document YAML (data), tree_data, and the linked Table DSL (table_data) so a form
# can be restored. Rollback restores the FORM DEFINITION only - table columns are left intact
# (additive), so no MongoDB record data is ever lost.
class EsmDocumentVersion < ActiveRecord::Base
  self.table_name = :esm_document_versions

  # protected_attributes is active in this app (see Table#attr_accessible).
  attr_accessible :document_id, :table_id, :data, :tree_data, :table_data,
                  :author_id, :author_name, :source, :note

  belongs_to :document
end
