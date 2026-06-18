# encoding: utf-8

class Service < ActiveRecord::Base
  
  self.table_name =  :esm_services
  attr_accessible :name,:package,:description,:params,:extended,:cache,:user_id,:project_id,:title,:acl
  
  has_many :operations, :dependent => :delete_all
  belongs_to :project
  validates_uniqueness_of :name, :scope => :project_id


  before_save :packaging
  def packaging
         self.package = "#{self.project.package}.#{self.name.camelize}".strip
  end


  def before_destroy
        self.operations.destroy_all
  end
  
 def display_name
        return title if self.title
        return name.humanize 
 end
  
  def to_s
       return self.name.classify
       return self.title if self.title
       return self.name.humanize  if self.name
       return 'Untitled'
  end
  
  def extended_list
      list = []
      service = self
      while service and service.extended and service.extended !=''
           service = Service.where("package=?",service.extended.strip).first
           list<<service
      end  
      return list     
  end
  
  def get_extended
    
    if self.get_extended
      return self.get_extended
    else
      project = self.project
      if project.extended
        sproject = project.get_super_project 
        if sproject
          ss = sproject.services.find_by_name self.name
          if ss
            return ss.package
          end
        end
      end
    end
    return ""
  end
  
  def self.get package, context=nil 
          
      unless context
        service = Service.where(:package=>package.strip).first() 
      end
      unless service
        t = package.split('.')
        name = t[-1].underscore
        project = Project.find_by_package(t[0..1].join('.'))
        instance = project.get_instance
        for i in instance[:services]
          if i.name == name
            s = Service.find(i.id) 
            s.project = project
          return s 
          end
        end
      end
      
      if service
      unless service.project
        service.destroy
        service = nil
      end 
      end
      return service if service
      return nil
  end
  
  
  
  def self.get_local name, context=nil 
         
        if context
          service = context[:project].services.find_by_name name.downcase
          return service if service
          return nil
       end
    
    end
  
  def prepare params, controller =nil, request = nil
    
    context = {}
    context = {:project=>self.project,:service=>self}
    context[:params] = params
    if controller
      # context[:domain]=controller.request.domain
      # context[:method]=controller.request.method
      # context[:session]=controller.session
      context[:controller]=controller
    end
    if request
      context[:request]=request
    end
    return context
  end
  
  def init context=nil
    load context
  end
  
  def load context=nil
          
  
  
  
  # build call stack        
  stack=[self]
  stack+=self.extended_list
          
superclass=<<EOF
# encoding: utf-8

class EsmSuperClass 
  
      attr_accessor :params,:context,:view

      def initialize context=nil
        @context = context
        @params = context[:params]
        @current_project =context[:project]
        @current_solution = @current_project.esm
      end

      def context
        @context
      end

      def params
        @params
      end

      def render_template command, this, p, layout=false        
        if layout
          command = "<% content_for :context_menu do %>\n\#{context_menu}\n <% end %>\n<% content_for :content do %>\n\#{command}\n <% end %> <% this = @context[:delegate] if @context[:delegate] %>\#{self.layout}<%=include_essential%>"
        end
        @command = command
         ctype = 'text/html'
         ctype = params[:content_type] if params[:content_type]
         
      (@context[:controller]).render(:inline=>command,:content_type=>ctype,:locals=>{:command=>command,:this=>this,:context=>@context,:params=>params})[0]
     end
      
      
      
      def layout
        if @context 
          home_service = @context[:project].get_service  'home'
          s = home_service.load @context 
          l = s.layout
          @context[:delegate] = s
          return l
        end
        return '<%=yield :content%>'  
      end
      
      def context_menu
        return ''        
      end
      
      def method_missing m, *params, &block
        return "No service"
      end
end
EOF



tmp=superclass

cache = false

# call stack
for s in stack.reverse
class_name=s.package.split('.').reverse.join      
program = ""
cache_path = Rails.root.join('tmp','cache',class_name+'.rb')
if cache and FileTest.exist? cache_path

file = File.open(cache_path,'r')
program = file.read()
file.close

# eval(program)
        
else

templates = {}        
ScriptTemplate.all.each do |i|
templates[i.id] = i
end

template = <<-EOF

class <%=class_name%> < <%="#{ s.extended && s.extended!="" ? s.extended.strip.split('.').reverse.join : 'EsmSuperClass'}"  %>

    def initialize context=nil
       super context
    end

    def local_class name
      "'\#{self.class.name}::\#{name}'"
    end

<% for m in s.operations(:includes=>[:script_template]) 
    if m.template_id %>
        def <%=m.name%> *params
            @params = params[0] if params[0]
            ret = <%=templates[m.template_id].generate m.command, self, @params  %>
        end
    <% else %>
        <%=m.command %>
    <% end %>
<% end %>
end
EOF

program = ERB.new(template).result(binding)
# file = File.open(cache_path,'w')
# file.puts program
# file.close 

end


tmp+= program


end

# puts tmp
#Service.send(:remove_const,"#{class_name}".to_sym)


eval(tmp)


return eval("#{class_name}.new context")

end
  
  def get_json_edit
    
  end
  
 
  def url domain=nil
         # "/esm/#{self.service.package}/#{self.name}"
         if domain and domain==self.project.domain
         return "/s/#{self.name.camelize}/index"
         else
         return "/esm/#{self.package.split('.').join('/')}/index"
        end
   end
   
   
   
   
   
   def xml_attr name, ele
     ele.elements.each("#{name}") { |element| self[name] = element.text }
   end
   
   
   def import ele , force=true
          xml_attr :name ,ele
          xml_attr :title ,ele
          xml_attr :description ,ele
          xml_attr :params ,ele
          xml_attr :extended ,ele
          
          self.save
       
       if force
               
                  self.operations.destroy_all
                  
                  ele.elements.each("operations/operation") do |element| 
             
                    op = self.operations.new
                    op.import element
                  end

        end
       
   end
   
   def self.export_options
    return {:include=>{:operations=>{:include=>{:script_template=>{:only=>[:name]}},:except=>[:id,:service_id,:template_id]}},:except=>[:user_id,:project_id,:id]}
   end
   
   def self.clean
       list = []
       Service.all do |s|
         
         unless s.project
            s.operations.each do |o|
              o.destroy
            end
            s.destroy
            list<<s
         end
          
       end
       return list
   end
  
  
  def get_acl opt_name, user

       #  
       s = self
       
       acl = []
       acl += self.acl.split if self.acl
       
       while s
          opt = s.operations.find_by_name opt_name
          if opt and opt.acl
            acl += opt.acl.split if opt.acl!=''
          end
          acl += s.acl.split if s.acl and s.acl!=''
          s = Service.find_by_package s.extended
       end
       
       
       # while s and opt==nil 
       #   opt = s.operations.find_by_name opt_name
       #   if opt
       #     acl += opt.acl.split if self.acl and self.acl!=''
       #     acl += s.acl.split if s.acl and s.acl!=''
       #   break
       #   
       #   s = Service.find_by_package s.extended 
       #   
       #   end    
       # end
       # 
      return acl
    
    
  end
  
  def authorize user, role = nil
    # - user login yes/no
    # - * for everyone
    # - 'blank' for owner
    # - 'user' for require login
    acl = []
    acl = self.acl.split if self.acl

    if user 
      # owner
      if self.project.esm.user == user
        return true
      elsif role and acl.index(role.name) or 
        return true
      end
    elsif acl.index '*'
      return true
    end
    return false
  end
  
end
      
   