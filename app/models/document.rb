require 'yaml'
require 'field'
require  "mime/types"
class Document < ActiveRecord::Base
  
  
  attr_accessible :name,:document_type,:data,:user_id,:project_id,:table_id,:sort_order,:published,:title,:acl,:tree_data
  
  

  self.table_name = :esm_documents
  belongs_to :project
  belongs_to :table
  belongs_to :service,:dependent => :delete
   
  attr_accessor :model,:fields

  before_save :before_save_func
  after_save :after_find_func
  after_initialize :after_find_func

  def get_model
    return self.project.load_model[self.table.name.to_sym]
  end

  def before_save_func
    
    unless @model
      @model = {}
      @fields = []
    end
      @model['fields'] = @fields.collect{|i| i.get_field_compression}
      self.data = YAML::dump(@model)
  end
  
  def refresh_structure data
    if data
       begin
         @model = YAML::load(data)
         if @model
                    
                 
            @fields =  @model['fields'].collect{|i|
                if i.instance_of? FIELDCOMPRESSION
                     
                f = Field.new 
                f.load_field_compression i
                i = f
                end                
                i if Field.field_types.index i.field_type
            }
           
         end
       # rescue Exception=>e
       #       puts e
        end
     end
     @fields = [] unless @fields
  end
  
  def after_find_func
    refresh_structure self.data
  end

  def add_field field
      field = Field.new field
      @fields<<field
      if field.column_name!="" and t = Field.data_types[field.field_type] and t!=nil
        self.table.add_column field.column_name, t
      end
      self.save
      return field 
  end
  
  def update_field id, params
    
    field = self.find_field id
    columns = self.table.data_columns
      
      
    if field.column_name!=params[:column_name] and !Field.visual_types.index(params[:field_type])
       if params[:column_name]!="" and !columns.index(params[:column_name]) and t = Field.data_types[params[:field_type]] and t!=nil
          self.table.add_column params[:column_name], t
        else
          return false
        end
    end
    field.update_attributes params
    self.save
  end
  
  
  def find_field field_id
    for i in @fields
      if i.id==field_id
        return i
      end
    end
    return nil
  end
  
  def find_by_column_name cname
    for i in @fields
      if i.column_name==cname
        return i
      end
    end
    return nil
  end
  
  def list_fields
    l = @fields
    lt = @fields.collect{|i| i if  i.list_show and i.list_show=='1'  }.compact
    l = lt if lt.size>0
    lt = l.collect{|i| i unless Document.visual_types.index(i.field_type) }.compact
    return lt
  end
  
  def list_fields_column_name
    self.list_fields.collect{|i| i.column_name}
  end
  
  def reorder fields
    list = []
    field = nil
    for i in fields
      if f = self.find_field(i)
        list<< f
      else
        field = Field.new({:field_type=>i,:style=>''})
        list<< field
      end 
    end
    @fields=list
    self.save
    return field
  end
  
  def get_mapping_master
          
           
           project = self.project
           
           list = [self.name]
           hash = {}
           
           for i in list_fields
           if i.field_type=='relation_one' or i.field_type=='relation_many' 
           params = eval("{#{i.params}}")
           if params[:relation]
           doc_name = params[:relation][:document]
           list<<doc_name
           end
          
           end
           
           for i in list
                 doc = project.get_document i
                 hash[i] = doc.get_mapping_values if doc
                 for j in doc.list_fields
                        hash[i][j.column_name+"_"] = j.id if j.column_name
                 end
           end
          return hash
        
        end
  end
  
  
  def get_mapping_values 
  
     res = {}
     
     for f in @fields
            lovs = f.get_lov_options
            if lovs
                h = {}
                for i in lovs
                      h[i[0]] = i[1]  
                end
                res[f.column_name] = h
            end

     end
     
     return res
  
  end
  
  # Post Action Processing
  # "record"=>{"module"=>"Supasak", "file"=>""}, "fields"=>{"many"=>{"1"=>{"name"=>"Kulawon", "value"=>"deief"}}}
  # fields=>{'camera'=>{"1"=>{"title"=>'xxx'}}}
  def filter_record_params model,params
      models = self.project.load_model

      #puts 
      #puts params.inspect 


      if params[:record]
         params[:record].each_pair do |k,v|
         field = find_by_column_name k
         if field
       # puts "Keyxxx : #{k}"
        #puts "Key : #{k} #{field.field_type}"
          case field.field_type
          when 'text_float', 'text_integer'

           if params[:record][k.to_sym] == ''
            params[:record][k.to_sym] =  nil           
           end       


          when 'relation_many'

           #puts "MANY #{self.name} #{params[self.name.to_sym].inspect} #{k}"
     	 # puts ""
  	 # puts ""       
            params[:record][k.to_sym] = ActiveSupport::JSON.decode(params[:record][k.to_sym])
            if params[self.name.to_sym] and params["na_#{k}".to_sym]==nil
            f = params[self.name.to_sym][k]
            if f
  	         
            value = Fields::RelationMany.filter_params(self,field,params[:record][k],f)
            #puts "============== #{value.inspect}"
            
              if value.size>0
                params[:record][k.to_sym] = value
              else
                params[:record][k.to_sym] = []
              end

            else
  	  # puts "$$$$$ many #{k}"
  	        params[:record][k.to_sym] = []
  	 
            end
  	      end
          when 'relation_one'
            # puts "ONE #{self.name} #{params[self.name.to_sym][k].inspect} #{k}"
            if params[:record][k.to_sym] and params[:record][k.to_sym] != "" 
              params[:record][k.to_sym] = BSON::ObjectId(params[:record][k.to_sym])
              if params[self.name.to_sym]
                f = params[self.name.to_sym][k]
                value = Fields::RelationOne.filter_params(self,field,params[:record][k],f)
        #        puts "============== one #{self.name.to_sym} #{value.inspect} k=#{k.inspect } #{params[:record][k.to_sym]} #{params[self.name.to_sym].inspect}"
                params[:record][k.to_sym] = value if value
             end
            else
              # no record [k] require new record to association
              puts 'New record has one'
               if params[self.name.to_sym] and params[self.name.to_sym][k]
                 tmpk = params[self.name.to_sym][k].keys[0]
                  f = params[self.name.to_sym][k] #[tmpk]
                  value = Fields::RelationOne.filter_params(self,field,params[:record][k],f)
                  params[:record][k.to_sym] = value if value

               end

            end

          when 'select_date' 
                if params[:record][k.to_sym]
                  a = params[:record][k.to_sym].split("/")
                  y = a[-1].to_i
                  if Time.now.year < y - 200
                    y -= 543
                    params[:record][k.to_sym] = a[0..1].join("/")+"/#{y}"
                  end
                end

          when 'image_camera','image_selection'
             params[:record][k.to_sym] = ActiveSupport::JSON.decode(params[:record][k.to_sym])
          else

            puts 'Other'

          end
         end 
         end
      end



      if params[self.name.to_sym]
        params[self.name.to_sym].each_pair do |k,v|
          field = find_by_column_name k
          value = nil
          if field
             case field.field_type
             when 'relation_many'
               # puts params[:record][k]
               #             puts v.inspect
               # value = Fields::RelationMany.filter_params(self,field,params[:record][k],v)
             when 'image_camera'
                ids = v[:id]
                uplist = {}
                att_m = models[:attachment]
                if params[:record][k] and data = params[:record][k]
                  for i in data
                    if ids.index i
                      uplist[i]=true
                    else
                      f = att_m.find(i)
                      f.destroy if f
                    end
                  end
                end
                ids.each_with_index do |i,index|
                  p = {:title=>v[:title][index]}

                  p[:selected] = v[:selected][i].to_i if v[:selected] and v[:selected][i]

                  # if uplist[i]
                    # update
                    att_m.find(i).update_attributes p
                  # end
                end
                value = v[:id]
                params[:record][field.column_name] = value

             end





          end
        end
      end

      params[:record][:id] = params[:object][:id] if params[:object]

      return params[:record]
    end
  
  

  
  # def create_record model=nil, params=nil
  #   if model
  #   return model.create filter_record_params(model,params)
  #   else
  #     puts '------------------------------------'
  #     puts model.inspect
  #     super
  #   end
  # end
  # 
  # def update_record model=nil, params=nil, record=nil
  #   record = model.find(params[:id]) unless record
  #   record.update_attributes filter_record_params(model,params) 
  #   return record
  # end
  
  def record_create model=nil, params=nil
    return model.create filter_record_params(model,params)
  end
  
  def record_update model=nil, params=nil, record=nil
    # puts ">>>>>>#{record.inspect}"          
    record = model.find(params[:id]) unless record
    # puts ">>>>>>222#{record.inspect}"  
    data = filter_record_params(model,params)      
    data.delete :id   
    # puts ">>>>data #{data}"
    record.update_attributes data 
    record.save
    # puts ">>>>>>333#{record.inspect}"          
    
    return record
  end
  
  # Model variable
  
  def self.version
    "0.0.1"
  end
  
  def self.field_types
    %w{ text_string 
        text_area 
        text_integer 
        text_float 
        text_grid
        select_string 
        select_integer 
        select_date 
        select_time 
        select_datetime
        check_string 
        check_integer 
        radio_string 
        radio_integer 
        image_marker
        image_note 
        image_camera
        image_selection 
        map_digitize 
        map_location 
        extra_signature 
        extra_attachment
        relation_one
        relation_many
        chapter 
        section 
        tab
        html
        clear }
  end
  
  def self.data_types
    { 
      
      'text_string' => 'String',
      'text_area' => 'String',
      'text_integer' => 'Integer',
      'text_float' => 'Float',
      'text_grid' =>'String',
      'select_string' => 'String',
      'select_integer' => 'String',
      'check_string' => 'String',
      'check_integer' => 'Integer',
      'radio_string' => 'String',
      'radio_integer' => 'Integer',
      'image_marker' => 'String',
      'image_camera' => 'Array',
      'image_note' => 'String',
      'image_selection'=>'Array',
      'select_date' => 'Date',
      'select_time' => 'Time',
      'select_datetime' => 'Datetime',
      'map_digitize'=>'String',
      'map_location' =>'String',
      'extra_signature'=>'String',
      'extra_attachment'=>'ObjectId',
      'relation_one' => 'ObjectId',
      'relation_many'=> 'Array',
      'chapter' => nil,
      'section' => nil,
      'tab' =>nil,
      'html'=>nil,
      'clear'=>nil

    }
    
    
  end

  
  def self.visual_types
    %w{section chapter clear html tab}
  end
  
  # Analysis
  
  def analysis_attributes

     list = []
     models = self.project.load_model
     # puts models.inspect 
     model = models[self.table.name.to_sym]

     for f in @fields
        unless Field.visual_types.index(f.field_type) 
           column_name = f.column_name
           att = {:type=>:attribute,:name=>f.column_name,:value=>[],:count=>''}
           case f.field_type

           when 'text_string','text_integer','text_float','select_string','select_integer','radio_string','radio_integer'
             att[:value]=[nil]
             l = {}
             rank = []
             model.all.each{|i|
               v = i[column_name]
               l[v] = 0 unless l[v]
               l[v] += 1
             }
             l.each_pair{|k,v|
               rank<<[v,k]
             } 
             rank.sort!{|a,b| b[0]<=>a[0]}
             5.times do |i|
               att[:value]<<rank[i][1] if rank[i]
             end
             att[:value].compact!
           end
           att[:values] = att[:value]
           att[:value]="[#{att[:value].size}]"

           list<<att
           for v in att[:values]
           count = model.where(column_name=>v).count
           att_v = {:type=>:attribute_value,:name=>f.column_name,:value=>v,:count=>count}
           list<<att_v
           end
        end
     end  
     return list
   end
   
   def attach_field_image field_id, filename, ssid, io, sort_order =0 ,ref =''
     return attach_field_file(field_id,filename,ssid,io,sort_order,ref)
   end
   
   def attach_image_restore att_id
     
     model = self.project.load_model[:attachment]
     att = model.find att_id
     
     if att and att.original_id
       att.update_attributes :file_id=>att.original_id, :thumb_id=>nil, :original_id=>nil
     end
     
     return att
   end
   
   def attach_image_update att_id, data
     
     model = self.project.load_model[:attachment]
     att = model.find att_id
     
     if att
       filename = att.filename   
       grid = Mongo::Grid.new(MongoMapper.database)
       id = grid.put(data,:filename=>filename)
       
       original_id = att.file_id
       
       if att.original_id
         original_id = att.original_id
         grid.delete att.file_id
       end 
       
       
       att.update_attributes :file_id=>id, :thumb_id=>nil, :original_id=>original_id
     end
     
     return att
     
      
   end
    
   
   def attach_field_file field_id, filename, ssid, io, sort_order = 0 ,ref =''
       
          
          model = self.project.load_model[:attachment]
          att = model.create :title=>'',:filename=>filename,:ssid=>ssid,:sort_order=>sort_order, :ref=>ref
          type = filename.split('.')[-1]
          # /public/esm/soluton/project/content/docs/[doc_name]/[field_name]/[attachmnet_id]
          field = find_field(field_id)
          
         
          
             p = ['content',self.project.content_path,self.name,field.column_name]
             path = p.join('/')
             filepath = '/'+File.join(path,"#{att.id}.#{type}")
            
             grid = Mongo::Grid.new(MongoMapper.database)
             
             
             #id = grid.put(io.read,:filename=>filename)
             
             # ==========================================================
             
             ext = filename.split(".")[-1]
             ext = 'jpg'
             
             id = nil
             
             if ext != 'jpg'
               
               id = grid.put(io.read,:filename=>filename)
               
             else
             
               rx = rand(9999999).to_s
               # filename= ofile.filename
               fname = "tmp/cache/#{rx}.#{ext}"
               rname = "tmp/cache/#{rx}_new.#{ext}"
               f = File.open(fname,'w')
               content = io.read.force_encoding('utf-8') 
               f.write content
               f.close
    
               size = '1920x1080' 
               puts `convert -resize #{size} #{fname} #{rname}`
               
               if FileTest.exist? rname
               
               file = File.open(rname,'r')
               content = file.read
               file.close
               File.delete fname
               File.delete rname
               
               id = grid.put(content,:filename=>filename)
             
               else
               
                 id = grid.put(content,:filename=>filename)
                 
               
               end
             
             end
             
             # ==========================================================
             
             
             # puts id.class
             tmp = {:title=>'',:filename=>filename,:path=>filepath,:file_id=>id, :ref=>ref}
             att.update_attributes(tmp)
             return att
          
     
          # txt = File.open('run.rb')
          
       
          
          
          # # att = model.create :title=>filename,:ssid=>ssid
          #          
          # # /public/esm/soluton/project/content/docs/[doc_name]/[field_name]/[attachmnet_id]
          #  field = find_field(field_id)
          #  p = [self.project.content_path,'docs',self.name,field.column_name]
          #  path = 'public'
          #  
          #  type = filename.split('.')[-1]
          #  # filepath = File.join(path,"#{att.id}.#{type}")
          #  id = grid.put(io.read,:filename=>filename,:metadata=>{:doc=>self.name,:field=>field.column_name,:type=>type,:path=>p.join('/')})
          #  
          #  # for i in p
          #  #   path = File.join(path,i)
          #  #   Dir.mkdir path unless FileTest.exist? path
          #  # end
          #  
          # 
          #  
          #  # File.open(filepath, "wb") { |file| file << io.read }
          #  # tmp = {:title=>filename,:path=>filepath[6..-1]}
          #  # att.update_attributes(tmp)
          #  return att
          
          
   end
   
   def rebuild_table
     
     self.table.update_attributes :data=>''
     
     for field in @fields
          if  t = Field.data_types[field.field_type] and t!=nil
             self.table.add_column field.column_name, t
          end
      end
     
   end
   def clone obj
          obj.deep_dup
   end
   def get_fields_node record = nil

           append_map = {}
           append_fmap = {}
           mirror = []
              
           f = @fields.collect{|i| 
           list = nil
           if i.lov_type and i.lov_type!= ''
                   list = []
                   case i.lov_type 

                   when 'plain'
                   	list = i.lov.split("\n").collect{|j|  [j.strip,j.strip]}
                   when 'pair'
                   	list = i.lov.split("\n").collect{|j| c = j.split("|");  c = [c[0],''] ; [c[0],c[1].strip] }
                   else
                   	list = []
                   end

                   list.collect!{|j| {text: j[1] , id:j[0] , spriteCssClass: "splashy-gem_okay"}}
           end

           cls = "splashy-application_windows_edit"
           case i.field_type
                when 'tab'
                cls='splashy-folder_modernist'
                when 'clear'
                i.name="clear[#{i.id}]"
                cls='splashy-breadcrumb_separator_arrow_2_dots'
                when 'section'
                # i.name="section[#{i.id}]"
                cls='splashy-breadcrumb_separator_arrow_2_dots'  
                # when 'text_float' ,'text_integer'
                #                 list = []
                #         10.times do |v|
                #                   list<<{text: v, id: "#{v}" }
                #           end
                #           10.times do |v|
                #                   sublist = []
                #                   v+=1
                #                   10.times do |w|
                #                           sublist<<{text: v*10+w, id: "#{v*10+w}"}
                #                   end
                #                   list<<{text: "+#{(v)*10}", id: "" ,items: sublist}
                #           end
                when 'relation_many'
                        
                        
                        cls = 'splashy-folder_modernist'
                     
                        
                        
                        if record
                                
                                has_one_model = Fields::RelationOne.get_instance self, i, record
                                table  = has_one_model.related_table    
                        	fields = has_one_model.related_fields
                        	doc = has_one_model.related_document

                        	doc_name = doc.name
                	
                        	selector = 'finding_type'
                        	
                        	related_map = {}
                        	selector_field = nil
                        	selector_field = doc.find_by_column_name selector
                        	if selector_field
                        	        selector_field.get_lov_options.each do |k|
                	                related_map[k[0]]=k[1]
                	                end
                	        end
                	
                        	related_data_node, related_fields_node, map, fmap,mirrorx = doc.get_root_format_node 
                                                              
                                
                                
                                value = record[i.column_name]
                  
                                if value and value.class == Array
                                        list = value.collect{|j| table.find(j)}.compact
                                        count = 0 
                                        # puts "Relation Mapping"
                                        # puts "#{map.to_yaml}"
                                        
                                        list.collect!{|j| 
                                                id = j['_id'].to_s
                                                name = id
                                                mirror << id
                                                sublist = []
                                                record
                                                # nmap = Marshal.load(Marshal.dump(map))
                                                # nmap =  map
                                                
                                                if selector_field
                                                        selected_value = j[selector]
                                                        name = related_map[selected_value]
                                                        
                                                        related_data_node[0][:items].each do |k|
                                                           if k[:id]==selector_field.id
                                                           sublist += clone(map["#{k[:id]}|#{selected_value}"][:items].collect{|i| map[i[:id]]})      
                                                           else
                                                           sublist << k.deep_dup
                                                           end
                                                        end
                                                        # relocation
                                                        
                                                        for k in sublist
                                                        old = k[:id]
                                                        k[:id] = "#{i.id}-#{id}-#{k[:id]}"
                                                        append_map[k[:id]] =  map[old]
                                                        append_fmap[k[:id]] = "#{self.name}-#{i.column_name}-#{id}-#{fmap[old]}"        
                                                        end
                                                else
                                                        name = doc.name
                                                        # puts "xxxxx #{related_data_node[0][:items].size}"
                                                        related_data_node[0][:items].each do |k|
                                                           sublist << k.deep_dup
                                                        end
                                                        # relocation

                                                        for k in sublist
                                                        old = k[:id]
                                                        k[:id] = "#{i.id}-#{id}-#{k[:id]}"
                                                        append_map[k[:id]] =  map[old]
                                                        append_fmap[k[:id]] = "#{self.name}-#{i.column_name}-#{id}-#{fmap[old]}"        
                                                        end
                                                        
                                                        
                                                end
                                                count += 1 
                                                 
                                                {text: name.strip, id: "#{i.id}-#{id}" , spriteCssClass: "splashy-gem_okay",items:sublist}
                                                
                                        }
                                        
                                 end
                            
                                 # puts list.to_yaml
                        
                       end
                 else      
                       
           end
           
           text = i.label
           text = i.name if text==nil or  text.index('@')
           
           if list 
                   r = {text: text , id: i.id ,spriteCssClass: cls, items: list }
           else
                   r = {text: text , id: i.id ,spriteCssClass: cls }
           end


           r

           }
           
           return f, append_map, append_fmap
        
   end
   
    def mapping node, fmap, umap={}


      fields = node['child']
      if fields
      	r = []

      	for i in fields
      		id = i['id']
      		f = fmap[id]
      		if f
      			r << f
      			umap[id] = true

      			if i['child']

      				if f[:items]
      					map = {}
      					kmap = {}
      					for j in i['child']
      						map[j['id']] = j
      					end

      					for k in f[:items]
      						kmap[k[:id]] = k
      					end

      					for j in f[:items]
      						v = map[j[:id]]
      						if v and v['child']
      							j[:items] = mapping(v, fmap,umap)
      							j[:expanded] = false
      						end				
      					end

      					if f[:items].size<i['child'].size

      						s = {'child'=>i['child'][-1-(i['child'].size-f[:items].size)..-1]}
      						f[:items]+= mapping(s, fmap,umap)

      					end



      				else
      					f[:items] = mapping(i, fmap,umap)
      					f[:expanded] = false
      				end


      			end



      		end

      	end

      	return r
      else
      	return nil
      end

      end
   
   def get_root_data_node record=nil
           
           root_data_node = [{text: "root",id:'root', expanded: true, spriteCssClass: "folder", items: []}]
           root_fields_node = [{text: "Fields",id:'fields', expanded: true, spriteCssClass: "folder", items: []}]

           tmap = {}
           fmap = {}
           
           
           @prefix = ''
           
           @fields.each do |field|
                  f_id = "#{@prefix}#{self.id}-#{field.id}"
                  unless Document.visual_types.index field.field_type
                           f_id = field.column_name
                  end
                  fmap[field.id] = f_id
           end
           
           fields,ntmap,nfmap = get_fields_node record
           
           tmap.merge! ntmap
           fmap.merge! nfmap
           
           umap ={}

           for i in fields
                  tmap[i[:id]] = i unless tmap[i[:id]]
           end

           tree_data = root_data_items = []

           if self.tree_data
                   # puts "xxxxx #{self.tree_data.inspect }"
                  tdata = eval(self.tree_data.gsub(':','=>')) 
                  tdata = [{'id'=>'root','child'=>[]}] if tdata==nil or tdata==[]
                  root_data_items = mapping(tdata[0], tmap,umap) 
           end

           root_data_node[0][:items] = root_data_items
           root_fields_node[0][:items] = fields.collect{|i| i unless umap[i[:id]] }.compact
           
          return root_data_node, root_fields_node, tmap, fmap
   end
   
   	def format_tree node

  		childs = node[:items]
  		if childs
  		r = []
  		for i in childs

  			if false && i[:id][0]!='F' or i[:id][1..-1].to_i==0 or (i[:spriteCssClass]=='splashy-breadcrumb_separator_arrow_2_dots' and i[:items]==nil)
                                
  			else
  			r << i
  			format_tree i
  			end
  		end
  		node[:items] = r
  		end

  	end

  	def mapping_tree map, node

  			if node[:id][0] == 'F'
  				map[node[:id]] = node
  			end

  			childs = node[:items]
  			if childs
  			for i in childs
  				map[node[:id]+'|'+i[:id]] = i if i[:id][0]!='F'
  				mapping_tree map, i
  			end
  			end

  	end
   
   # 
   
   
   def get_root_format_node record = nil
           
         tree_data, root_fields_node, map, fmap = self.get_root_data_node record
        
        
        root_data_node = tree_data.deep_dup
      
        # format_tree root_data_node[0]
        mapping_tree map, tree_data[0]
  
        
      
   return root_data_node, root_fields_node, map, fmap
   
  end
  
end
