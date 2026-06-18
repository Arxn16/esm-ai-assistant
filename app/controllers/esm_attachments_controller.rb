class EsmAttachmentsController < EsmController
  
  protect_from_forgery :except => [:upload]
  
  before_filter :context_filter, :except=>[:show]
  def show
    package = params[:package].split('/')
    # package = [params[:solution_name],params[:project_name]] + params[:package].split('/')
    # package = "#{params[:solution_name]}/#{params[:project_name]}/#{package}"
    # puts "xxxx#{package}"
    esm = Esm.find_by_name package[0]
    project = esm.projects.find_by_name package[1]
    model = project.attachment_model
    att =  model.find params[:id] 
    grid = Mongo::Grid.new(MongoMapper.database)
    
    # file = grid.get(BSON::ObjectId.from_string(att.file_id))
    # puts att.file_id.class
    
    
    file = nil
    content = nil
    
    if params[:thumb] 
    
      if att.thumb_id == nil or (file = grid.get(att.thumb_id) )== nil or params[:thumb]=='2'
           ofile = grid.get(att.file_id)
           ext = ofile.filename.split(".")[-1]
           ext = 'jpg'
           filename= ofile.filename
           fname = "tmp/cache/#{att.file_id}.#{ext}"
           rname = "tmp/cache/#{att.file_id}_thumb.#{ext}"
           f = File.open(fname,'w')
           f.write ofile.read.force_encoding('utf-8') 
           f.close
           size = '128x128'
           size = '256x256' if params[:thumb]=='2'
           size = '1280x720' if params[:thumb]=='hd'
           puts `convert -resize #{size} #{fname} #{rname}`
           file = File.open(rname,'r')
           content = file.read
           file.close
           File.delete fname
           File.delete rname
           id = grid.put(content,:filename=>filename)
           # puts "new id #{id}"
           att.update_attributes :thumb_id=>id
           file = grid.get(att.thumb_id)
           
     else
        content = file.read     
     end
    
              
      
    else
            file = grid.get(att.file_id)
            content = file.read
    end
    
    
    
   
    
    render :text=>content,:content_type=>file.content_type
    
  end
  

  
  def upload
    @document = Document.find(params[:id])
    @project = Project.find(params[:p_id])
    @document.project = @project
    if request.post?
      
      field_id = params[:field_id]
      atts = @document.attach_field_file field_id,params[:upload][:file].original_filename,params[:ssid],params[:upload][:file], 0 ,params[:ref]
       respond_to do |format|
          format.html {render :action=>'upload.html',:layout=>nil}
          format.json {render :text=>{:id=>atts.id,:path=>atts.path,:status=>'ok'}.to_json}
       end
      
    else
      render :action=>'upload.html',:layout=>nil
    end
  end
  
end