require 'digest/sha1'

class User < ActiveRecord::Base

attr_accessible :login,:hashed_password,:email,:salt,:last_accessed,:activate,:role_id,:esm_id

  belongs_to :role
  belongs_to :esm
  has_many :esms
  has_many :accounts
   
  validates_length_of :login, :within => 3..40, :on => :create
  validates_length_of :password, :within => 5..40 , :on => :create
  validates_presence_of :login, :email, :password, :password_confirmation, :salt , :on => :create
  
  validates_uniqueness_of :login, :email
  
  validates_confirmation_of :password , :on => :create
  # validates_format_of :email, :with => /^([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})$/i, :message => "Invalid email"  , :on => :create,:multiline => false 
  
  # after_create :after_create_filter
  # 
  # def after_create_filter
  #   self.esms.create :name=>self.login if self.id
  # end
  before_validation :filter_before_validation

  def filter_before_validation
    self.email = self.login if self.email==nil  and self.login.index('@')
  end

  attr_protected :id, :salt

  attr_accessor :password, :password_confirmation
    
  def self.authenticate(login, pass)
    u=  self.where("login = ? and (activate is null or activate != 0  )", login).first()
    return nil if u.nil?
    if User.encrypt(pass, u.salt)==u.hashed_password
      u.last_accessed = Time.now
      u.save
      return u
    end
    nil
  end
  
  def get_account_by_project p
    p.accounts.find_by_user_id self.id
  end 
  
  def developer_of_project p
    
    return true if self.role == 'Admin'
    return true if p.user.login == self.login
    a = p.accounts.find_by_user_id(self.id)
    puts a.to_json
    return false unless a
    return true if a.group.name == 'developer'
    return false
  end 

  def password=(pass)
    @password=pass
    self.salt = User.random_string(10) if !self.salt?
    self.hashed_password = User.encrypt(@password, self.salt)
  end
  
  def send_new_password
    new_pass = User.random_string(10)
    self.password = self.password_confirmation = new_pass
    self.save
    Notifications.deliver_forgot_password(self.email, self.login, new_pass)
  end

  
  def default_home
    
    return self.role.default_home if self.role and self.role.default_home
    '/'
    
  end
  
  def self.mock_user user, solution
        @mock_user = user
        
        u = User.new
        u.id = user.id
        u.login = user.login + "#{u.id}"
        u.email = user.email if user.email
        u.esm_id = solution.id
        
        # return user
        
        return u
        
  end
  
  
  def get_name context
    if context
      unless self.login.index(DOMAIN)
        return self.login
      else
        return self.login[0..self.login.index('@')-1]
      end
    else
      return "#{self.login} (#{self.role.name if self.role })"
    end
  end
  
  def my_solutions
    
    list = [self.esm]
    list += self.esms
    list += self.accounts.collect{|i| i.esm if i.role.developer? }
    list.compact
    
  end
  
  
  def authorize? solution
    
     return solution.user == self if solution
    
  end
  
  def developer? solution = nil
     return ((self.role and (self.role.name == 'admin' or self.role.name == 'developer')) or (solution and (solution.user == self or solution.developer?(self)))) 
  end
  
  def self.encrypt(pass, salt)
    Digest::SHA1.hexdigest(pass+salt)
  end
  
  def to_s
      self.login
    end
  
  def allow? r, acl
          
          return true if r=='developer' or acl==nil or acl==''
          acl = acl.split(",").collect{|i| i.strip}
          acl << 'user' if acl.size==0
          role = 'user'
          role = r if r 
          
          return acl.index role
          
        
  end
  
  
  protected


  
  def self.random_string(len)
    #generat a random password consisting of strings and digits
    chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
    newpass = ""
    1.upto(len) { |i| newpass << chars[rand(chars.size-1)] }
    return newpass
  end
  
  
 
  

  
end
