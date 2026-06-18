module Fields
class RelationOne < Relation
  
  def self.test
    return Time.now
  end
  # Post Action Processing
  # "record"=>{"module"=>"Supasak", "file"=>""}, "fields"=>{"many"=>{"1"=>{"name"=>"Kulawon", "value"=>"deief"}}}
  # params = 1=>{"name"=>"Kulawon", "value"=>"deief"}}}
  def self.filter_params document,field,value,params
    
    fparams = eval("{#{field.params}}")
    doc = document.project.get_document(fparams[:relation][:document])
    model = document.project.load_model[doc.table.name.to_sym]
    
    puts params.inspect 
     
    if fparams[:relation] and params
      
      if fparams[:relation][:partial] 
         list = []
         # for i in value
         list<<model.find(value)
         # end
         return ''# list.collect{|i|i.id}
      else
      if value 
          # for i in value
            a = model.find(value)
            a.destroy if a
          # end
      end
      list = []
      params.each_pair do |k,p|
        
        p.each_pair do |k,v|
         field = doc.find_by_column_name k

          case field.field_type
          when 'image_selection'
            puts "image_selection #{v.inspect}"
            if v and v!='' 
              p[k] = ActiveSupport::JSON.decode(v)
            else
              p[k] = []
            end
          else
          end
        end
        
   
        
        list<<model.create(p)
      end
      
      # return list.collect{|i|i.id}
      
      return list[0].id
      
      end
      
    end
    
    return nil
    
  end
end
end