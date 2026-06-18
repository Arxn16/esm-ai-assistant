class EsmDocumentsController < EsmDevController

  skip_before_filter  :verify_authenticity_token

 def index 
   @project = Project.find(params[:id])
   render_to_panel :partial=>'list.html'
 end
 
 
 def show
    @document = Document.find(params[:id])
    @project = @document.project 
    render_to_panel :partial=>'show.html',:layout=>'/esm_documents/local.html'
 end
 
 
 def new
   @project = Project.find(params[:id])
   @document = @project.documents.new
   if request.post?
     
     table = @project.get_schema.tables.find_or_create_by(:name=>params[:table_name])
     if table
       params[:document][:table_id] = table.id
     end
     @document = @project.documents.create params[:document]
     
     
      # inherit from template
       service = @document.project.services.create :name=>@document.name.downcase.split.join('_'),:title=>@document.title,:extended=>'system.util.Document'
       menu_action = @document.project.menu_actions.create :name=>@document.title, :url=>"../#{@document.name.classify}/index"
       operation = service.operations.build :name=>'document_name', :command=>"'#{@document.name}'",:template_id=>ScriptTemplate.find_by_name('ServiceTemplate').id
       operation.save
       @document.service = service
       @document.save
     
     
     
     reload_workspace :controller=>'esm_documents',:action=>'show',:id=>@document
     
   else
     render_to_panel :partial=>'new.html'
   end
 end
 def edit
    @document = Document.find(params[:id])
    @project = @document.project
    if request.post?
      if params[:fields]
          params[:fields].each_pair do |k,v|
           field = @document.find_field k
           field.update_attributes v
          end
      end
      if params[:document][:data]
        @document.refresh_structure params[:document][:data]
      end
      @document.update_attributes params[:document]
      reload_workspace :controller=>'esm_documents',:action=>'show',:id=>@document
    else
      render_to_panel :partial=>'edit'
    end
 end
 def destroy
    @document = Document.find(params[:id])
     @project = @document.project
     @document.destroy
     reload_workspace :controller=>'esm_documents',:action=>'index',:id=>@project
 end
 
 def rebuild_table
   @document = Document.find(params[:id])
   @document.rebuild_table
   render_to_panel :partial=>'show.html',:layout=>'/esm_documents/local.html'
   # reload_workspace :controller=>'esm_documents',:action=>'index',:id=>@document.project   
 end

 def show_layout
   @document = Document.find(params[:id])
   @project = @document.project 
   render_to_panel :partial=>'show_layout.html',:update=>'layout'
 end
 
 def edit_layout
     @document = Document.find(params[:id])
     if request.post?
       @document.update_attributes params[:document]
       if params[:fields]
            params[:fields].each_pair do |k,v|
             field = @document.find_field k
             field.update_attributes v
            end
        end
        @new_field = @document.reorder(params[:field])
     end
     render_to_panel :partial=>'edit_layout.html',:update=>'workspace',:layout=>'local'
 end

 def edit_tree
     @document = Document.find(params[:id])
     if request.post? and params[:document]# and params[:document][:tree_data]!=''
       @document.update_attributes params[:document]
       # if params[:fields]
       #             params[:fields].each_pair do |k,v|
       #              field = @document.find_field k
       #              field.update_attributes v
       #             end
       #         end
       #         @new_field = @document.reorder(params[:field])
     end
     render_to_panel :partial=>'edit_tree_layout.html',:update=>'workspace',:layout=>'local'
 end


 
 def refresh_layout options=nil
   unless @document
   @document = Document.find(params[:id])
   end
   @edit = true
   @options = options
   render_to_panel :partial=>'edit_layout.html',:update=>'workspace',:layout=>'local'
   
 end
 

 def field_new
     @document = Document.find(params[:id])
     @field = Field.new
     if request.post?
       field = @document.add_field params[:field]
       refresh_layout :edit=>field
     else
     render_to_panel :partial=>'field_new.html'
   end
 end
 
 def field_edit
    @document = Document.find(params[:id])
    @field = @document.find_field params[:field_id]
  
    if request.post?
       if @document.update_field params[:field_id],params[:field]
         refresh_layout
       else
         flash[:error] = 'The column name has been add'
         refresh_layout
       end
     else
       render_to_panel :partial=>'field_edit.html'
     end

 end
 
 def field_delete
    @document = Document.find(params[:id])
    @field = @document.find_field params[:field_id]
    @document.fields.delete @field
    @document.save
    refresh_layout
 end




  
end