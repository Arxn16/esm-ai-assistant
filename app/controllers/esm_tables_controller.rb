class EsmTablesController < EsmDevController

  
  def index
    @project = Project.find(params[:id])
    @schema  = @project.schema
    @tables = @schema.tables
    render_to_panel :partial=>'list.html'
  end
  
  
  def new
        @project = @context.projects.find(params[:id])
        @schema  = @project.schema
        @table = @schema.tables.new
          if request.post?
                  @table.update_attributes params[:table]
                  reload_workspace
          else
          render_to_panel :partial=>'new.html'
        end
  end
  
  
  def show
    
       @table = Table.find(params[:id])
        @project = @table.schema.project
        render_to_panel :partial=>'edit.html'

  end
  
  
  
  def edit
    @table = Table.find(params[:id])
    @project = @table.schema.project
    if request.post?
        @table.update_attributes params[:table]
        render_to_panel :partial=>'/esm_services/updated.html'
    else
        render_to_panel :partial=>'edit.html'
    end
  end
  
  def destroy
    @table = Table.find(params[:id])
    @project = @table.schema.project
    @table.destroy
     reload_workspace   :controller=>'esm_tables',:action=>'index',:id=>@project
  end

  
end