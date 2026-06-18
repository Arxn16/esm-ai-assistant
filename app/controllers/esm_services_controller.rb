class EsmServicesController < EsmController

  before_filter :login_required
  layout 'esm_application'
  
  before_filter :workspace
  def workspace
      params[:update]='workspace' unless params[:update]
  end
  
  def reload_workspace urls = nil
    
    @url = url_for urls if urls
    render_to_panel :partial=>'/esm_home/reload_workspace'
    
  end
  
  def index
    @project = @context.projects.find(params[:id])
    @services = @project.services
    render_to_panel :partial=>'list'
  end
  
  
  def new
        @project = @context.projects.find(params[:id])
        @service = @project.services.new
        if request.post?
                @service.update_attributes params[:service]
                reload_workspace :controller=>'esm_services',:action=>'show',:id=>@service
        else
        render_to_panel :partial=>'new'
      end
  end

  
  def show
        @service = Service.find(params[:id])
        @project = @service.project
        @operation = @service.operations.find(params[:op_id]) if params[:op_id]
        render_to_panel :partial=>'show'
  end
  
  def edit
        @service = Service.find(params[:id])
        @project = @service.project
        if request.post?
         @service.update_attributes params[:service]
         reload_workspace
        else
        render_to_panel :partial=>'edit'
      end
  end
  
  def destroy
        @service = Service.find(params[:id])
        @project = @service.project
        @service.destroy
        reload_workspace      
  end
  

  # import export
  
  def migrate 
    
     @service = Service.find(params[:id])
      @project = @service.project
      if request.post?
       require "rexml/document"
       
       REXML::Document.new(params[:service][:data]).elements.each("service") do |element| 
         puts element
          @service.import element
       end
       render_to_panel :partial=>'migrate'
       
       # reload_workspace
      else
      render_to_panel :partial=>'migrate'
    end
    
  end
  
end