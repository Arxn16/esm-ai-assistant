class RenameEsmServices < ActiveRecord::Migration
  def up
          rename_column(:esm_services,:service_id,:extended)
  end

  def down
          rename_column(:esm_services,:extended,:service_id)
  end
end
