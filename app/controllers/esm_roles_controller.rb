class EsmRolesController < EsmDevController
  
  def index 
     @project = Project.find(params[:id])
     render_to_panel :partial=>'index.html'
   end

   def show
      @role = Role.find(params[:id])
      @project = @role.project 
      render_to_panel :partial=>'show.html'
   end
   def new
     @project = Project.find(params[:id])
     @role = @project.roles.new
     if request.post?
       @role = @project.roles.create params[:role]
       # render :
       reload_workspace :action=>'show',:id=>@role
     else
       render_to_panel :partial=>'new.html'
     end
   end
   def edit
      @role = Role.find(params[:id])
      @project = @role.project
      if request.post?
        @role.update_attributes params[:role]
        reload_workspace :action=>'show',:id=>@role
      else
        render_to_panel :partial=>'edit.html'
      end
   end
   def destroy
       @role = Role.find(params[:id])
       @project = @role.project
       @role.destroy
  reload_workspace :action=>'index',:id=>@project
   end  

  
end