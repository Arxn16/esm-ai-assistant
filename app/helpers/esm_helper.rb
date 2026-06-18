module EsmHelper
  
  def version(text)
    "ESM Essential"
  end
  
  def include_template
    render :partial=>'esm/template'
  end

  def show_datetime date
    return date.strftime("%d-%m-%Y %H:%M")
  end
  def menu_link_to name, url, options={}
    extra = ""
    extra += ",iconCls:'#{options[:iconCls]}' " if options[:iconCls]
    
    if options[:remote]
      render :text=>"{text:'#{name}' #{extra} ,handler:function(){
      $.ajax({url: '#{url}',success: function(data){eval(data);}});}}"
    else
      render :text=>"{text:'#{name}' #{extra} ,handler:function(){window.location='#{url}';}}"
    end
  
  end
  
  def render_panel title,width=300,height=400
    render :partial=>'/shared/panel',:locals=>{:title=>title,:width=>width,:height=>height}
  end
  
  def remote_function url,options=nil
    render :partial=>'/esm/remote_function',:locals=>{:url=>url_for(url),:options=>options}
  end
  
    def model_columns model
      model.columns.collect{|c| c.name if c.name!='created_at' and c.name!='updated_at'}.compact
    end


  # arrange col in row by col then block 
    def format_data model,data, &block
      data.collect{|row|  
          tmp=model.collect{|c| 
            s = ''
            s = row[c] if row[c] 
            s
           }
          tmp=yield(row,tmp) if block
          tmp
      }
    end

    def format_data_crud model,data,&block
      format_data model,data do  |row,out|
      out<<link_to('Show', row)
      out<<link_to('Edit', :action=>'edit',:id=>row)
      out<<link_to('Delete', row, :confirm => 'Confirm?', :method => :delete)
      yield(row,out) if block
      out
      end
    end
  
  def tabular params, &block

    model=params[:model]
    data=params[:data]

    # clean model
    model=model_columns params[:model] if model.respond_to? 'columns'
    # format data
    # puts 'yyyyy'+data.inspect 
    
    if params[:crud]
      data=format_data_crud model,data,&block
    else
      data=format_data model,data,&block
    end

    # puts 'xxxxx'+data.inspect 
    params[:model]=model
    params[:data]=data
    
    
    partial='esm/tabular'
    partial=params[:partial] if params[:partial]
    render :partial=>partial,:locals=>params
  end
  
  def show_menu data
    @menus = data
    render :partial=>'/esm/menu'
  end
  
  def methodize name, name2=nil
    r = "javascript:$('\##{name}').val(this.value.toLowerCase().replace(/ |\\*|\\-|\\(|\\)/gi,'_'));" 
    r += "javascript:$('\##{name2}').val(this.value.toLowerCase().replace(/ |\\*|\\-|\\(|\\)/gi,'_'))" if name2
    return r
  end
  
  def icon name
    image_tag("/esm/icon/#{name}.png")
  end
    
    
  def bt_class
     'k-button'
  end  
 
 def tb_class
    'k-textbox k-textbox-txt'
 end
 def ta_class
    'k-textarea'
 end
 
 def include_header
    render :partial=>'/esm/header'    
 end
 
 def include_essential
    render :partial=>'/esm/essential'    
 end
    
    def is_active_controller(controller_name)
         params[:controller] == controller_name ? "active" : nil
     end

     def is_active_action(action_name)
         params[:action] == action_name ? "active" : nil
     end
    
end