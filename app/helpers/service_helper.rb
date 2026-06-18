module ServiceHelper
  
        def fm money
            number_to_currency(money, :unit => "", :format => "%n")
        end

        def fu money
          if money
          a = number_to_currency(money, :unit => "", :precision=>3, :format => "%n")
          if a[-1]=='0'
            a = number_to_currency(money, :unit => "", :precision=>2, :format => "%n")
          end
          a
          else
            return ""
          end
        end

        def fn unit
          number_to_currency(unit, :unit => "",:precision => 0, :format => "%n")
        end
  
        def thmonth month
          months = %w{ มกราคม กุมภาพันธ์ มีนาคม เมษายน พฤษภาคม มิถุนายน กรกฎาคม สิงหาคม กันยายน ตุลาคม พฤศจิกายน ธันวาคม}
          return months[month-1]
        end
  
        
        def thdate date =nil
          
            date = Time.now unless date
          
            months = %w{ มกราคม กุมภาพันธ์ มีนาคม เมษายน พฤษภาคม มิถุนายน กรกฎาคม สิงหาคม กันยายน ตุลาคม พฤศจิกายน ธันวาคม}
            month = months[date.month-1]
            year = date.year+543

           return "#{date.day} #{month} #{year}"
          
          
        end
        
        

        def thnumber  n

          a = <<EOF
          ศูนย์
          หนึ่ง
          สอง
          สาม
          สี่
          ห้า
          หก
          เจ็ด
          แปด
          เก้า
          สิบ
          ยี่
          เอ็ด
          ร้อย
          พัน
          หมื่น
          แสน
          ล้าน
EOF

          a = a.split("\n").collect{|i| i.strip}

          t = n

          lt100 = n%100
          gt100 = (n/100)%10
          gt1000 = (n/1000)%10
          gt10000 = (n/10000)%10
          gt100000 = (n/100000)%10
          gt1000000 =(n/1000000)%10


          if lt100 < 11
            t = a[lt100]
          else
            i = lt100%10
            j = lt100/10


            x = "#{a[j]}#{a[10]}"
            x = "#{a[11]}#{a[10]}" if j == 2
            x = "#{a[10]}" if j == 1


            y = a[i]
            y = a[12] if i == 1 
            y = "" if i==0 

            t = "#{x}#{y}"
          end

          t = "#{a[gt100]}#{a[13]}#{t}" if gt100>0
          t = "#{a[gt1000]}#{a[14]}#{t}" if gt1000>0
          t = "#{a[gt10000]}#{a[15]}#{t}" if gt10000>0
          t = "#{a[gt100000]}#{a[16]}#{t}" if gt100000>0
          t = "#{a[gt1000000]}#{a[17]}#{t}" if gt1000000>0

          return t
        end
  
  
    def url path, options=nil
      if options
      op = '?'+URI.escape(options.keys.map{|i| "#{i}=#{options[i]}"}.join('&'))
      else
      op = ''
      end 
      context = @current_object.context
       p = path.split('?')
       t = p[0].split('/')
       if t.size==2
          if t[0].downcase==context[:service].name 
            return "../#{context[:service].name.camelize}/#{t[1]}#{op}"
          else 
            return "../#{path}#{op}" 
          end
       else
          return "../#{context[:service].name.camelize}/#{t[0]}#{op}"
       end  
    end
    
    def delegate path, context=nil
      context = @current_object.context 
      p = path.split('/')
      s = Service.get_local p[0], context
      s = s.load 
      l = s.layout
      return l.html_safe
    end

   def default_layout default="default"
    if default!='default'
        render :partial=>"/layouts/inspinia"
    else
    unless params[:partial]
      render :partial=>"/layouts/layout"
    else
      render :partial=>"/layouts/partial"
    end
    end
   end
   
   
   def get_service name
    return @current_project.get_service name
   end
   
   def get_model name=nil
     model = @current_project.load_model name
     return model

   end
   
   def get_document name
     return @current_project.get_document name
     # return @current_object.context[:project].get_document name
   end
   
   # render_value 'field_name', :label=>false
   
   
   def render_value column_name, options=nil
      field = @document.find_by_column_name column_name
      @field = field
      render(:partial=>'/esm_documents/show_value',:locals=>{:field=>field,:record=>@record,:column_name=>column_name,:opt=>options})
   end
   
   def get_has_one_value column_name, document=nil, record=nil
     
      document = @document unless document
      record = @record unless record
     
      field = document.find_by_column_name column_name
      fparams= eval("{#{field.params}}")
      path = fparams[:relation][:document].to_s.split('#')
    	doc_tag = path.split('.')


    	if path.size==1 # local document   ex : patient
    		doc_name = path[-1]
    		doc =document.project.get_document doc_name
    		table = document.project.schema.load_model[doc.table.name.to_sym]

    	elsif doc_tag.size==1 # other project document  ex : ehr#patient
    		doc_name = path[-1]
    		project = document.project.esm.get_project doc_tag[0]
    		doc = project.get_document doc_name
    		table = project.load_model[doc.table.name.to_sym]
    	end

    	fields = doc.list_fields_column_name
    	fields = fparams[:relation][:fields] if fparams[:relation][:fields]

    	if table
    	  return table.find(record[column_name]),doc	
    	end
      return nil
      
   end
   
   def get_has_one_value_from_collection column_name, collection
     
      document = @document unless document
      map = {}
     
      field = document.find_by_column_name column_name
      fparams= eval("{#{field.params}}")
      path = fparams[:relation][:document].to_s.split('#')
    	doc_tag = path.split('.')


    	if path.size==1 # local document   ex : patient
    		doc_name = path[-1]
    		doc =document.project.get_document doc_name
    		table = document.project.schema.load_model[doc.table.name.to_sym]

    	elsif doc_tag.size==1 # other project document  ex : ehr#patient
    		doc_name = path[-1]
    		project = document.project.esm.get_project doc_tag[0]
    		doc = project.get_document doc_name
    		table = project.load_model[doc.table.name.to_sym]
    	end

    	fields = doc.list_fields_column_name
    	fields = fparams[:relation][:fields] if fparams[:relation][:fields]

    	if table
    	  for i in collection
    	    map[i.id] = table.find(i[column_name])	
  	    end
    	  return map
    	end
      return nil
      
   end
   
   def get_has_many_value column_name, document=nil, record=nil
     
      document = @document unless document
      record = @record unless record
     
      field = document.find_by_column_name column_name
      fparams= eval("{#{field.params}}")
      path = fparams[:relation][:document].to_s.split('#')
    	doc_tag = path.split('.')


    	if path.size==1 # local document   ex : patient
    		doc_name = path[-1]
    		doc =document.project.get_document doc_name
        # table = document.project.schema.load_model[doc.table.name.to_sym]
    		
    		table = doc.get_model
        
    	elsif doc_tag.size==1 # other project document  ex : ehr#patient
    		doc_name = path[-1]
    		project = document.project.esm.get_project doc_tag[0]
    		doc = project.get_document doc_name
    		table = project.load_model[doc.table.name.to_sym]
    	end

    	fields = doc.list_fields_column_name
    	fields = fparams[:relation][:fields] if fparams[:relation][:fields]

    	if table
    	  list = []
    	  list = record[column_name] if record[column_name]
    	  return table.find(list),doc	
    	end
      return nil
      
   end
   
   def get_setting name
    @current_project.setting name
   end
   
   def link_to_upload *p
     p = p[0]
     id = p[:id]
     
   link_to_function("upload", "return popitup('#{url_for(:controller=>'esm_attachments',:id=>id,:action=>'upload',:fid=>p[:fid],:callback=>p[:callback])}','Upload','height=200,width=300')" )
   end
   
   
   def enqueue_job *params
     
     require 'resque'
     require 'job'
     
     Resque.enqueue(Job::JobTest, params)
    
   end
   
   def view cmd, option=nil

    case cmd
    when :fitwidth
      return '<script>jQuery("body").addClass("gebo-fixed");jQuery("body").addClass("sidebar_hidden_force");jQuery("#sidebar_bt").hide();	</script>'.html_safe
    when :fullscreen
      return '<style type="text/css" media="screen">.div960{width:100%;}</style><script>jQuery(".mainwrapper").addClass("lefticon-hidden");</script>'.html_safe
    when :fullwidth
      return '<style type="text/css" media="screen">.div960{width:100%;}</style>'.html_safe
    when :fitscreen
      return '<style type="text/css" media="screen"></style><script>jQuery(".mainwrapper").addClass("lefticon-hidden");</script>'.html_safe
      
    end
   end


	def	chart cmd, options = {}
		
		unless options[:data]
		
		data = [['2011/7/21','x','1'],['2011/7/21','x','1'],['2011/7/21','y','1'],['2011/7/21','x','2'],
		['2012/7/21','x','1'],['2012/7/21','x','3'],['2012/7/21','x','1'],['2012/7/21','x','2']]
		x = ['x','y','z']
		y = ['1','2','3']
		n = 1000
		1000.times do |i|

			data << [(Time.now+(rand(n)-n/2)*3600).strftime('%Y/%m/%d'),x[rand(3)],y[rand(3)]]

		end
		end

		title = 'Patient Type'
		tooltip = '#= series.name # #= value #'
	    value_axis = "\#= value \#"
	    colors = ["#ff0000", "#ff6666", "#ffaaaa",
	                   "#00ff00", "#66ff66", "#aaffaa",
					   "#0000ff", "#6666ff", "#aaaaff"]
		
		title = options[:title] if options[:title]
		tooltip = options[:tooltip] if options[:tooltip]
		value_axis = options[:value_axis] if options[:value_axis]
		colors = options[:colors] if options[:colors]
		data = options[:data] if options[:data]
		
		
		render :partial=>"/esm/charts/#{cmd}",:locals=>{:title=>title,:tooltip=>tooltip,:data=>data,:value_axis=>value_axis,:colors=>colors}
	end
   
end