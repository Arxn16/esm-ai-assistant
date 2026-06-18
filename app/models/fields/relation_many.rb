module Fields
class RelationMany

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
    
     
    if fparams[:relation] and params
      
      if fparams[:relation][:partial] 
        list = []
         for i in value
            list<<model.find(i)
         end
         return ''# list.collect{|i|i.id}
      else
        
        
      map = {}
        
      if value 
          for i in value
            a = model.find(i)
            # a.destroy if a
            map[a.id.to_s] = a if a
            
          end
      end
      list = []
      params.each_pair do |id,p|
        
        
        
        
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
        
          
        if m = map[id.to_s]
          m.update_attributes(p)  
          list << m
        else  
          list << model.create(p)
        end
      
      end
      return list.collect{|i|i.id}
      end
      
    end
    
    return []
    
  end
end
end