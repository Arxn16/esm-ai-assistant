class EsmDevController < EsmController

  before_filter :login_required ,:except=>[:snap,:recover,:barcode,:snap_update]
  layout 'esm_application'
  
  before_filter :workspace
  def workspace urls = nil
     @url = url_for urls
      params[:update]='workspace' unless params[:update]
      
      
  end
  
  def reload_workspace urls = nil
    @url = url_for urls if urls
    render_to_panel :partial=>'/esm_home/reload_workspace.html'  
  end


end