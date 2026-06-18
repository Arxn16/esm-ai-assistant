FIELD = Struct.new(:id, :name, :label, :column_name,:search,:list_show,:mandatory, :field_type,:params,:display,:css,:style,:default, :lov_type, :lov ,:description )  unless defined? FIELD
# , :container_id,:sort_order,:hide_label,:model_path, :model_format
FIELDCOMPRESSION = Struct.new(:attributes)

class Field < FIELD
  
  attr_accessor :container
  
  def initialize params=nil
     if params
       params[:id]="F#{format('%010d',rand(9999999999))}"
        self.update_attributes params
     end
     return self
  end
   
  def update_attributes params
    
    if params['name']!=nil and params['name']!=''
      if params['column_name']==nil or params['column_name']=="" 
        params['column_name']=params['name'].downcase.split.join('_')
      end
      if params['label']==nil or params['label']=="" 
        params['label']=params['name']
      end
    elsif params['column_name']
      params['name']= params['column_name'].humanize
      params['label']= params['column_name'].humanize
    else
      params.delete 'label'
    end
    for i in self.members
      self[i] = params[i] if params[i]
    end
  end
  
  def self.version
    Document.version
  end
  
  def self.field_types
    Document.field_types
  end
  
  def self.data_types
    Document.data_types
  end
  
  def self.visual_types
    Document.visual_types
  end
  
  def get_field_compression 
        list = [:id, :name, :label, :column_name,:search,:list_show,:mandatory, :field_type,:params,:display,:css,:style,:default, :lov_type, :lov ,:description]
        attrs = {}
        for i in list
        
        if self[i] != '' and self[i] != nil  
           attrs[i] = self[i]
        end
        # puts "xx #{i.inspect } #{self[i]}"
         if ([:search, :list_show, :mandatory].index(i) and self[i]=='0')
          # puts "xx  #{i.inspect } #{self[i]}"
          attrs[i] = nil
          attrs.delete i
          # field.attributes.delete i
        end
        end
        field = FIELDCOMPRESSION.new
        field.attributes = attrs
        return field
  end
  
  def load_field_compression comp
           
          list = [:id, :name, :label, :column_name,:search,:list_show,:mandatory, :field_type,:params,:display,:css,:style,:default, :lov_type, :lov ,:description]
          attrs = comp.attributes
          # puts attrs.inspect
          for i in list
             self[i] = attrs[i] if attrs[i]
          end
          
    end
  
  
  def get_lov_options
        
         options = nil
        
        if self.lov_type
 	        if self.lov_type == 'plain'
 	                options = self.lov.split("\n").collect{|i| [i.strip,i.strip] }.compact
                elsif self.lov_type == 'pair'
 	                options = self.lov.split("\n").compact.collect{|i| j = i.split('|');j }
                else
                
                end
        end
        return options
        
  end
  
  
  
  
end