require 'barby'
require 'barby/barcode/code_128'
require 'barby/barcode/ean_13'
require 'barby/barcode/code_39'
require 'barby/barcode/qr_code'
require 'barby/outputter/png_outputter'

class EsmImageController < EsmDevController
  protect_from_forgery :except => [:snap,:recover,:snap_update]

  def snap_update
    
     # puts params.inspect
     @project = Project.find(params[:p_id])
    
     doc = Document.find(params[:id])
    
     @document = @project.get_document doc.name
    
     # atts = @document.attach_field_image field_id,filename,params[:ssid],image,params[:sort_order].to_i,params[:ref]
     image = request.body
     if params[:image]
       image = params[:image]
     end
    
     att = @document.attach_image_update params[:att_id], Base64.decode64(image)
    
     render :text=>att.to_json,:content_type=>'application/json'
     
  end


  def snap_restore
    
     # puts params.inspect
     @project = Project.find(params[:p_id])
    
     doc = Document.find(params[:id])
    
     @document = @project.get_document doc.name
    
     # atts = @document.attach_field_image field_id,filename,params[:ssid],image,params[:sort_order].to_i,params[:ref]
    
    
     att = @document.attach_image_restore params[:att_id]
    
     render :text=>att.to_json,:content_type=>'application/json'
     
  end

  def snap 
    puts params.inspect
    @project = Project.find(params[:p_id])
    
    doc = Document.find(params[:id])
    
    @document = @project.get_document doc.name
    
    if request.post? and request.body
      field_id = params[:field_id]
    
      
      filename = "#{params[:snapcount]}.jpg"
      
      
      image = request.body
      
      if params[:image]
        image = params[:image]
      end
      head = {}
      if defined? image.headers
      image.headers.split("\r\n")[0].split(":")[-1].split(";").each do |i|
             t = i.split('=').collect{|j|j.strip}
             head[t[0].to_sym] = t[1]
      end
      end
      # puts "%%%%%#{head}"
      
      params[:sort_order] = Time.now unless params[:sort_order]
      filename = "#{head[:filename] }" if head[:filename] 
      params[:sort_order] = "#{head[:order]}" if head[:order]
      
      
      
      
      
      atts = @document.attach_field_image field_id,filename,params[:ssid],image,params[:sort_order].to_i,params[:ref]
      atts = true if atts
      render :text=>atts.inspect
      
     else
      params[:ssid] = Time.now.to_i
    end
  end
  
  def download
          
        @project = Project.find(params[:p_id])
        doc = Document.find(params[:id])
        @document = @project.get_document doc.name
        field = @document.find_field params[:field_id]
        record = nil
        list = []
        if field
                record = @document.get_model.find(params[:record_id])
                list = record[field.column_name]
                
                model = @project.attachment_model
                images = model.find list 
                grid = Mongo::Grid.new(MongoMapper.database)

                file = nil
                content = nil
                atts = []
                for i in images
                        ofile = grid.get(i.file_id)
                        ext = ofile.filename.split(".")[-1]
                        fname = "tmp/cache/#{i.file_id}.#{ext}"
                        f = File.open(fname,'w')
                        f.write ofile.read.force_encoding('utf-8') 
                        f.close
                        atts << fname
                end
                tarfile = "tmp/cache/#{record.id}.zip"
                `zip #{tarfile} #{atts.join(" ")}`
                
                  # if params[:thumb] 
                  # 
                  #                     if att.thumb_id == nil or (file = grid.get(att.thumb_id) )== nil
                  #                          ofile = grid.get(att.file_id)
                  #                          ext = ofile.filename.split(".")[-1]
                  #                          ext = 'jpg'
                  #                          filename= ofile.filename
                  #                          fname = "tmp/cache/#{att.file_id}.#{ext}"
                  #                          rname = "tmp/cache/#{att.file_id}_thumb.#{ext}"
                  #                          f = File.open(fname,'w')
                  #                          f.write ofile.read.force_encoding('utf-8') 
                  #                          f.close
                  #                          puts `/usr/local/bin/convert -resize 128x128 #{fname} #{rname}`
                  #                          file = File.open(rname,'r')
                  #                          content = file.read
                  #                          id = grid.put(content,:filename=>filename)
                  #                          # puts "new id #{id}"
                  #                          att.update_attributes :thumb_id=>id
                  #                          file = grid.get(att.thumb_id)
                  # 
                  #                    else
                  #                       content = file.read     
                  #                    end
                
        end
          
        
        send_data File.open(tarfile,'r').read,:type => 'application/octet-stream',
           :disposition => "attachment; filename=#{tarfile}"
  end
  
  
  def recover 
    @project = Project.find(params[:p_id])
    
    doc = Document.find(params[:id])
    
    @document = @project.get_document doc.name
    
    
    
      @attachment_model = @project.get_model :attachment
    
    if request.post? and request.body
      field_id = params[:field_id]
      filename = "#{params[:snapcount]}.jpg"
      
      image = request.body
      
      if params[:image]
        image = params[:image]
      end
      
      atts = @document.attach_field_image field_id,filename,params[:ssid],image
      atts = true if atts
      # render :text=>atts.inspect
      
     else
      params[:ssid] = Time.now.to_i
      
      

      
    end
  
    
  end
  
  def attach_to_gallery
    
    @project = Project.find(params[:p_id])
    @document = Document.find(params[:id])
    model = @project.load_model[:attachment]
    @field = @document.find_field(params[:field_id])
    @name = "#{@document.name}[#{@field.column_name}]"    
    
    unless params[:a_id]
      
     if params[:attachment] 
    
             @attachments = model.find(params[:attachment])
     
     else     
             ssid = params[:ssid].to_i
             @attachments = model.where('$or'=>[{:ssid=>ssid.to_i},{:ssid=>ssid.to_s}]).sort(:sort_order).all
     end
    
    
    
    else
      @attachments = [model.find(params[:a_id])]
    end
    
    # render :text=>'alert("ok")'
    
    render :partial=>'attach_to_gallery'
  end

  def barcode

    mode = 'code_128'
    mode = params[:type] if params[:type]
    barcode = nil
    case mode
    when 'code_128'
      barcode = Barby::Code128B.new(params[:code])
    when 'code_39'
      barcode = Barby::Code39.new(params[:code])
    when 'ean_13'
      barcode = Barby::Ean13.new(params[:code])
    when 'qr_code'
      barcode = Barby::QrCode.new(params[:code])
    end
    code = params[:code].split("/").join("-")
    xdim = 2
    xdim = params[:xdim].to_i if params[:xdim]
    xdim = 1 if xdim <1
    height = 50
    height = params[:height].to_i if params[:height]
    height = 30 if height < 30
    margin = 5
    margin = params[:margin].to_i
    # name = File.join("tmp","#{Time.now.to_i}.#{code}.#{mode}.png")
    # File.open(name, 'w'){|f| f.write  }
    content = barcode.to_png :xdim => xdim, :height => height, :margin =>margin

    render :text=>content,:content_type=>'image/png'
  end

  



end

