require "rexml/document"
class EsmHomeController < EsmController

  before_filter :login_required
  layout 'esm_application'
  
  before_filter :workspace
  def workspace
      params[:update]='workspace' unless params[:update]
  end
  
  def index
    
  end
  
  def import
    
    if request.post?

      cmd = params[:import][:file].read
      
      REXML::Document.new(cmd).elements.each("project") do |element| 
        path = ""
        element.elements.each("package") { |e| path = e.text }
        project = Project.find_by_package path
        if project 
          project.import element
        else
          project = @context.projects.create :package=>path
          project.import element
        end
        
    end
      
      
    end
    
    redirect_to :action=>'index'
    
  end
  
  def project
        @project = Project.find(params[:id])
        @context = @project.esm
        @current_project = @project
  end
  
  
  
  
  def esm_new
    @esm = @current_user.esms.new
    if request.post?
      @esm = @current_user.esms.create params[:esm]
      @esm.projects.create :name=>'www',:title=>'Www'
      if @esm!=nil
        session[:esm]= @esm.id
        redirect_to :action=>'index'
      else
        flash[:error]='error'
      end
    end
  end
  
  def esm_switch
    @esm = Esm.find(params[:id])
    session[:esm]=@esm.id
    redirect_to :action=>'index'
  end
  
  def esm_edit
    
    @esm = @current_user.esms.find(params[:id])
    
    if request.post?
      # params[:esm][:name] = "#{@current_user.login}_#{params[:esm][:name]}"
      # @esm = @current_user.esms.create params[:esm]
      # session[:esm]= @esm.id
      @esm.update_attributes params[:esm]
      redirect_to :action=>'index'
    end
  end
  
  def esm_delete
    if @current_user.role and @current_user.role.name == 'admin'
      @esm = Esm.find(params[:id])
    else  
      @esm = @current_user.esms.find(params[:id])
    end
  
    session[:esm]=nil
    @esm.destroy
    redirect_to :action=>'index'

  end

  def reload_workspace
    unless @project
      @project = @context.projects.find(params[:id])
    end
    @current_project = @project
    # render :text=>'window.location.reload()'
    render_to_panel :partial=>'project.html',:update=>'content_panel'
  end
  

  
  def user_new
    @project = Project.find(params[:id])
    @esm = @project.esm
  
    
    
  end
  
  
  
  
end