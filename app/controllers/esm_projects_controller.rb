class EsmProjectsController < EsmDevController

  before_filter :login_required
  layout 'esm_application'
  
  before_filter :workspace
  def workspace urls = nil
    
     @url = url_for urls
      params[:update]='workspace' unless params[:update]
  end
  
  def index

  end
  
  def refresh
    @project = Project.find(params[:id])
    @context = @project.esm
    @current_project = @project
    render_to_panel :partial=>'show'
  end
  
  def show
      
        @project = Project.find(params[:id])
        @context = @project.esm
        @current_project = @project
        
        # if @current_project.esm.user==@current_user or (@current_user.role and  @current_user.role.name=='admin')
        if @current_project.esm.developer?(@current_user)
          
        respond_to do |format|
          format.html {render :show}
          format.json {render 'show.json'}
          format.js   {render_to_panel :partial=>'show',:update=>'main_content'}
        end
        
        else
          redirect_to '/user/logout'
        end
  end
  
  def new
         @project = @context.projects.new
         if request.post?
                 @project.update_attributes params[:project]
                 if @project.save
                         redirect_to :action=>'show',:id=>@project
                 end
         end
   end

   def edit
         @project = @context.projects.find(params[:id])
         if request.post?
                 @project.update_attributes params[:project]
                 if @project.save
                    
                    if params[:settings]
                      @project.update_settings params[:settings]
                    end
                   
                    if params[:setting]
                      @project.settings.create params[:setting]
                    end
                    @project.get_refresh_instance
                         render_to_panel :partial=>'edit',:id=>@project
                 end
         else
         
         render_to_panel :partial=>'edit'
       end
         
   end

   def destroy
         @project = @context.projects.find(params[:id])
         @project.destroy
         redirect_to :controller=>'esm_home',:action=>'index'
   end


   def add_setting
        
     @project = @context.projects.find(params[:id])
     @setting = @project.settings.new
      render_to_panel :partial=>'add_setting'
      
   end
   
   
   def delete_setting
        
     @project = @context.projects.find(params[:id])
     setting = Setting.find(params[:oid])
     setting.destroy
     @settings = @project.get_instance[:settings]
     
     render_to_panel :partial=>'settings'
      
   end
  
end