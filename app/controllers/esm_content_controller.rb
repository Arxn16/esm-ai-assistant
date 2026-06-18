

class EsmContentController < EsmDevController


def index
  render :action=>'index',:layout=>'file_manager'
end

def data
  
    @project = Project.find(params[:id])
  
   h, r = ElFinder::Connector.new(
     :root => File.join(Rails.public_path, 'esm',@project.esm.name, @project.name),
     :url => "/esm/#{@project.esm.name}/#{@project.name}",
     :perms => {
       'forbidden' => {:read => false, :write => false, :rm => false},
       /README/ => {:write => false},
       /pjkh\.png$/ => {:write => false, :rm => false},
     },
     :extractors => {
       'application/zip' => ['unzip', '-qq', '-o'],
       'application/x-gzip' => ['tar', '-xzf'],
     },
     :archivers => { 
       'application/zip' => ['.zip', 'zip', '-qr9'],
       'application/x-gzip' => ['.tgz', 'tar', '-czf'],
     },
     :thumbs => true
   ).run(params)

   headers.merge!(h)
   render (r.empty? ? {:nothing => true} : {:text => r.to_json}), :layout => false
 end

def show
  @project = Project.find(params[:id])
  render_to_panel :partial=>'index.html',:update=>'workspace'
end



end