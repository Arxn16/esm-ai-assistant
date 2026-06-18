class EsmDocumentController < EsmController

  before_filter :login_required
  # layout 'esm_application'
  
  def partial_create

     init_patial_model

     if request.post?

        init_ref_model

         if @ref_record and @field

            @record = @document.record_create(@model,params)
            @records<<@record.id
            @ref_record.update_attributes @field.column_name=>@records
         end

         @records = @records.collect{|i| @model.find(i)}.compact

         render_to_panel :partial=>'/esm_documents/partial_list.html',:update=>@field.id
      else
         render_to_panel :partial=>'/esm_documents/partial_new.html'
     end
  end

  def partial_update
    init_patial_model
    @record = @model.find(params[:p_id])
     if request.post?
         init_ref_model
         if @ref_record and @field
            @record = @document.record_update(@model,params,@record)
         end
         @records =@records.collect{|i| @model.find(i)}.compact
         render_to_panel :partial=>'/esm_documents/partial_list.html',:update=>@field.id
      else
         render_to_panel :partial=>'/esm_documents/partial_edit.html'
     end
  end



  def partial_delete


     init_patial_model
     init_ref_model
     
     @record = @model.find(params[:p_id])
     id = @record.id.to_s
     @record.destroy
     
     
     
     
     # @document = Document.find(params[:id])
     # @table = @document.get_model
     # @record = @table.find(params[:p_id])
     # @record.destroy
     # 
     # @ref_tag = params[:ref_tag]
     # ref_tag = params[:ref_tag].split('|')
     # 
     # @ref_doc = Document.find(ref_tag[0])
     # @ref_record = @ref_doc.get_model.find(ref_tag[1])
     # @field = @ref_doc.find_field ref_tag[2]
     # @fid = @field.id
     # 
     # t = @ref_record.send(@field.column_name)
     # records = t if t
     @records -= [id]
     @records = @records.collect{|i| @model.find(i)}.compact
     records = @records.collect{|i| i.id}
     @ref_record.update_attributes @field.column_name=>records

     render_to_panel :partial=>'/esm_documents/partial_list.html',:update=>@field.id

  end

  def partial_show
     @document = Document.find(params[:id])
     @project = @document.project
     @ref_tag = params[:ref_tag]
     @table = @document.project.load_model[@document.table.name.to_sym]
     if request.post?
         render_to_panel :partial=>'/esm_documents/partial_show.html'
     end
  end



  def init_patial_model
     ref_tag = params[:ref_tag].split('|')
     @current_project =Project.find_by_package(ref_tag[0])
     doc = Document.find(params[:id])
     @document = @current_project.get_document doc.name
     @project = @document.project
     @model = @document.get_model
     @ref_tag = params[:ref_tag]
     return @document
  end

  def init_ref_model 
     
     ref_tag = params[:ref_tag].split('|')
     @current_project =Project.find_by_package(ref_tag[0])
     @ref_doc = @current_project.get_document(ref_tag[1])
    
     @ref_record = @ref_doc.get_model.find(ref_tag[2])
    
     @field = @ref_doc.find_field ref_tag[3]

     if @ref_record and @field
         puts @ref_doc.inspect
            puts @ref_record.inspect
       
       @fid = @field.id
       value = @ref_record.send(@field.column_name)
       @records = value if value
       @records = [] unless @records
    
     end
  end

  def relation_has_one_search
    
     @project =  Project.find(params[:p_id])
     
     @document = @project.get_document params[:id]
     @field = @document.find_field params[:f_id]
     @record = @document.project.load_model[@document.table.name.to_sym].find(params[:r_id])
     render_to_panel :partial=>'relation_has_one_search',:update=>'search-result'
  end
  
  def relation_has_many_add
      @project =  Project.find(params[:p_id])
      @document = @project.get_document params[:id]
      @field = @document.find_field params[:f_id]
      @link_field = @field
      @record = @document.project.load_model[@document.table.name.to_sym].find(params[:r_id])
      params[:position]=:after
      @i = "New "
      render_to_panel :partial=>'relation_has_many_add',:update=>"#{params[:f_id]}",:animate=>'slideDown'
      
  end
  def relation_has_many_remove
    
      render :text=>"a = $('\##{params[:id]}'); a.slideUp('fast',function(){a.remove()}); " 
      # @document = Document.find(params[:id])
      # @field = @document.find_field params[:f_id]
      # @record = @document.project.load_model[@document.table.name.to_sym].find(params[:r_id])
      # params[:position]=:after
      # render_to_panel :partial=>'relation_has_many_add',:update=>"#{params[:f_id]}"
      
  end
  
end