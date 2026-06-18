class Permission < ActiveRecord::Base
  
  attr_accessible :name,:menu_action_id,:role_id
  
end
