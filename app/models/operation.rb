

class Operation < ActiveRecord::Base
  
  
  attr_accessible :name,:service_id,:template_id,:command,:description,:auto_test,:snippet,:title,:acl
  
  self.table_name = :esm_operations
  belongs_to :service
  belongs_to :script_template,:foreign_key=>'template_id'

  validates_uniqueness_of :name, :scope => :service_id
  def to_s
       return self.title if self.title and self.title!=""
       return self.name.humanize  if self.name
       return 'Untitled'
  end
  after_initialize  :init
  before_save :escape
  def init
     self.command = self.command.gsub(/(\\\\#)/, '\#') if self.command   
  end

  def escape
    self.command = self.command.gsub(/\#{/, "\\\#{")
  end
  
  def edit_mode
          self.command = self.command.gsub(/(\\\#)/, '#') if self.command
  end
  
  def url domain=nil
        # "/esm/#{self.service.package}/#{self.name}"
        if domain and domain==self.service.project.domain
        return "/s/#{self.service.name.camelize}/#{self.name}"
        else
        return "/esm/#{self.service.package.split('.').join('/')}/#{self.name}"
       end
  end
  
   def xml_attr name, ele
      ele.elements.each("#{name}") { |element| self[name] = element.text }
   end
   
   
   def import ele , force=true
     
       xml_attr :name , ele
       xml_attr :title ,ele
       xml_attr :command ,ele
       xml_attr :description ,ele
            
       ele.elements.each("script-template/name") { |element| 
        self.template_id = ScriptTemplate.find_by_name(element.text).id 
       }  
            
       self.save

   end
   
   def authorize user, role = nil,  s = nil
     
     # - user login yes/no
     # - * for everyone
     # - 'blank' for owner
     # - 'user' for require login
     acl = []
     if self.acl
       acl = self.acl.split 
     else
       acl = s.acl.split
     end
    
     if acl.index '*'
       return true
     elsif user 
       if s.project.esm.user == user
         return true
       elsif role and acl.index '*' or acl.index(role.name)
         return true
       end
     end
     return false
   end
  
end

