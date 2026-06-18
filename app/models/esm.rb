class Esm < ActiveRecord::Base
  
  
  attr_accessible :name,:title,:url,:sort_order,:published,:default_project,:user_id
  
  
  belongs_to :user
  has_many :roles
  has_many :users
  has_many :logs
  has_many :settings, :dependent => :delete_all
  has_many :menu_actions, :dependent => :delete_all
  # has_many :permissions, :dependent => :delete_all
  has_many :projects ,:dependent => :delete_all
  
  validates_uniqueness_of :name
  
  scope :published, -> { where(:published => true)}
  # scope :dry_clean_only, joins(:washing_instructions).where('washing_instructions.dry_clean_only = ?', true)
  def before_destroy
        self.projects.destroy_all
  end
  
  def to_s
        self.name.humanize  if self.name
  end
  
  before_validation :filter_before_save
  
  def filter_before_save
    
    # self.name = "#{self.user.login}_#{self.title}" if self.user
    # if !self.name or self.name==""
    # self.name = self.user.login if self.user
    # if self.user.esms.find_by_name self.name  
    #   self.name = "#{self.user.login}_#{self.title.tableize.split().join('_')}" if self.title
    # end
    # end
  end
  
  after_create :filter_after_create
  
  
  
  def filter_after_create
    
    # project = self.projects.create :name=>'www',:title=>'Www'
    
  end
  
  
  def get_user_by_id id
          
          user = nil
          role = nil 
          
          return get_user_role_by_id id
        
  end
  
  def get_user_role_by_id id
          
          user = nil
          role = nil 
          solution_user = nil
          
          if id.size<10
                  user = User.find(id)
                  role = Role.new :name=>'user'
          else
                  www = get_www
                  user,role = www.get_user_by_id id
                  if user
                    solution_user = user
                    user = User.mock_user user, self
                  end
                  
          end
          
          return user,role,solution_user
        
  end
  
  
  def self.get_solution name
    self.find_by_name name
  end
  
  def default_home request
    project = self.projects.find_by_name 'www'
    if project
        return project.get_home_url request
    else
        return '/esm_home'
    end
  end
  
  def get_www
        return get_project 'www'
  end
  
  def get_home_url request
    default_home request
  end
  
  def get_project name
    self.projects.find_by_name name
  end
  
  def get_projects_by_abstract package
    list = []
    self.projects.all.each do |i|
    
      if i.extended==package
        list<<i
      else
             #    
             project = i
             # while project and project.extended
             while project and project.extended and project.extended!=""
             super_project = Project.find_by_package project.extended
             #list<<super_project
             if super_project and super_project.extended==package
                  list << i 
             end
             project = super_project
             end
    end
    end
    list
  end
  
  def developer? user
    return true if self.user == user or (user.role and user.role.name=='admin')
     # list = self.roles.find_all_by_name 'developer'
    list = self.roles.where(:name=>'developer').all
    
    
    for i in list
      if acc = i.accounts.find_by_user_id(user.id)
        return acc
      end
    end
    return false 
  end
  
  def db_name
    return "#{MONGO_PREFIX}-#{self.name}"
  end
  
  
  def get_users
    return self.users
  end
  
  def create_user user_attributes, opt=nil
     @user = User.new user_attributes
     @user.save
  end
  
  def get_user_role user, opt=nil
    
  end
  
  def get_roles
    
  end
  
  def create_role name, opt=nil
    
  end
  
  
  
  
end
