class AdminController < EsmController

  before_filter :login_required
  
  def index
    @current_project = @context.projects.find(params[:id])
    @project = @current_project
    
  end
  
  def show  
    @current_project = @context.projects.find(params[:id])
    @project = @current_project
  end
  
  def project
    @current_project = @context.projects.find(params[:id])
    @project = @current_project
    
    render :action=>'show.html'
  end
  
end