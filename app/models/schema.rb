class SchemaProxy < Hash
   
   attr_accessor :schema,:project
   
   def initialize schema, project
           @schema = schema
           @project = project
   end
   
   def [](i)
        # puts "REQUEST Proxy #{i}"
        @schema.load_model @project, i.to_s
   end
        
end

class Schema < ActiveRecord::Base
  self.table_name =  :esm_schemas
  belongs_to  :project
  has_many :tables
  

  
  attr_accessible :name,:esm_id,:project_id,:schema_type,:source
  
  def attachment_model
    load_model nil, :attachment
  end
  
  def load_model project_instance = nil, model_name= nil
    
   # puts "load model #{model_name}"
    
    tables = []
    if model_name == :attachment
            
          
       # tables = Table.find(project_instance[:tables].collect{|i| i  if i.name==model_name  }.compact)
      
    elsif model_name
       
      list = [model_name]
           
      
      doc = project_instance[:documents].collect{|i| i if model_name == i.name }.compact[0]
      # puts model_name 
      if doc
      for i in doc.fields
              if i.field_type == 'relation_one' or i.field_type == 'relation_many' and i.params and i.params!='' and model_name!='attachment'
                p = eval("{#{i.params}}")
                table = p[:relation][:document]
                list << table
              end
      end
      end
      list.uniq!
   
      
      tables = Table.find(project_instance[:tables].collect{|i| i  if i.name==model_name  }.compact.collect{|j| j.id})
   # puts "xxx #{tables.inspect}"
    elsif project_instance
      # tables = Table.find(project_instance[:tables])
      tables = project_instance[:tables].collect{|i| Table.find(i.id)}
      
    else         
      tables = self.tables
    end
    

 unless model_name
         # puts "CREATE Proxy"
         return SchemaProxy.new self, project_instance
         
 else
      # puts "REQUEST #{model_name} #{tables.size}"
       template =<<EOF
       
class MongoConnect 
    include MongoMapper::Document
end 
 
MongoMapper.database  = '<%=self.project.esm.db_name%>'



class Attachment < MongoConnect
  
  # attr_accessible :title,:path,:project_id,:ssid,:file_id
  
  set_collection_name "<%=self.project.name%>.attachment"
  
  # def self.read_inheritable_attribute *params
  #    # class_attribute *params
  # end
  # def self.write_inheritable_attribute *params
  #    # class_attribute *params
  #  end
  
  
  
  key :title,String
  key :selected,Integer
  key :params,String
  key :ref,String
  key :filename,String
  key :path,String
  key :project_id,Integer
  key :ssid,String
  key :file_id,ObjectId
  key :thumb_id,ObjectId
  key :original_id,ObjectId
  
end
       
<% for i in tables %>
class <%= i.name.camelize %> < MongoConnect
  
  set_collection_name "<%=self.project.name%>.<%=i.name%>"

  <%= i.data %>
  
  timestamps!

end
<% end %>

<% for i in tables %>
class <%= i.name.camelize %> < MongoConnect

<%= i.command %>

end
<% end %>



{:attachment=>Attachment,<%= tables.collect{|i| ":\#{i.name}=>\#{i.name.camelize}" }.join(',')%>}
EOF

       command = ERB.new(template).result(binding)
       # puts command
      
       models = eval(command)
     unless model_name
       return models
     else
       return models[model_name.to_sym]
     end
    
  end
  
  
  
  end
  

end

# def self.read_inheritable_attribute *params
#   # class_attribute *params
# end
# def self.write_inheritable_attribute *params
#    # class_attribute *params
#  end
#  
# attr_accessible :public_id,:hn