module Fields
class Relation < ActionView::Base
  # extend ApplicationHelper
  # extend ActionView::Helpers
  
  attr_accessor :document, :field, :record, :related_document, :related_table,:related_fields, :path
  
  def initialize document, field, record=nil
      
      self.document = document
      self.field = field
      self.record = record
      
      fparams = eval("{#{field.params}}")
     
      path = fparams[:relation][:document].to_s.split('#')
      self.path = fparams[:relation][:document].to_s
    	doc_tag = path.split('.')

    	if path.size==1 # local document   ex : patient
    		doc_name = path[-1]
    		self.related_document = self.document.project.get_document doc_name
    		self.related_table = self.document.project.load_model()[self.related_document.table.name.to_sym]
    	elsif doc_tag.size==1 # other project document  ex : ehr#patient
    		doc_name = path[-1]
    		project = document.project.esm.get_project doc_tag[0]
    		self.related_document = project.get_document doc_name
    		self.related_table = project.load_model(self.related_document.table.name)[self.related_document.table.name.to_sym]
    	end
    	self.related_fields = self.related_document.list_fields_column_name
    	self.related_fields = fparams[:relation][:fields] if fparams[:relation][:fields]
    	
    	    	
    	
    
  end
  
  
  def self.get_instance document, field, record=nil
    
    @relation_map = {} unless @relation_map
    
    fparams = eval("{#{field.params}}")
    path = "#{document.project.name}\##{fparams[:relation][:document].to_s}"
    
    unless object = @relation_map[path]
      object = Fields::RelationOne.new document,field,record
      @relation_map[object.path] = object
    end
    return object
  end
  
end
end