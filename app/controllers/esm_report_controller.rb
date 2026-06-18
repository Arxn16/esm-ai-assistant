class EsmReportController < EsmController
 
  before_filter :workspace
  def workspace
 
      params[:update]='workspace' unless params[:update]
  end
  def analysis
    @document = Document.find(params[:id])
    @current_project = @document.project
    
    render_to_panel :partial=>'analysis.html',:layout=>'local',:update=>'workspace'
  end
 
end
