class MenuAction < ActiveRecord::Base
  
  attr_accessible :name,:label,:action_category,:parent_id,:action_type,:url,:sort_order,:published,:esm_id,:project_id,:acl
  
  scope :published, ->{where(:published => true)}
  scope :root, ->{where(:parent_id=>nil, :published=>true)}
  has_many :menu_actions, :foreign_key=>'parent_id'
  belongs_to :project 
  
end
