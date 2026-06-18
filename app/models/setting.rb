class Setting < ActiveRecord::Base
  attr_accessible :name,:value,:description,:esm_id,:project_id,:group
  belongs_to :project
  
end
