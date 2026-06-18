# encoding: utf-8
class EsmProxyController < EsmController
 
  skip_before_filter :verify_authenticity_token
 
 include EsmHelper
 include ServiceHelper
 
 # before_filter :login_required,:except=>'ws'
 
 def index2
        render :text=>Time.now
 end
 
def index
    s = nil
    
    
    if @current_solution 
       MongoMapper.database= @current_solution.db_name
     else
       MongoMapper.database="esm-"+params[:package].split('/')[0]
    end
    
    grid = Mongo::GridFileSystem.new(MongoMapper.database)
    
    static_content = nil
    
    begin   
    grid.open(request.path_info,'r') do |f|
      static_content = f.read
    end
    rescue 
    end

    if static_content 
      render :text => static_content, :content_type=>f.content_type
    else
 
    @mode = :app
    if params[:service]
       s = Service.get("#{@current_project.package}.#{params[:service]}") 
    else
       s = Service.get(params[:package].split('/').join('.')) 
    end
  
    if s
       
       begin 
       
       @current_service = s
       @current_project = s.project
       @current_solution = @current_project.esm
       @context = @current_solution
       opt = s.operations.find_by_name params[:opt]
       
       if @current_user
       elsif params[:user_id]
         
          @current_user = User.where(:id=>params[:user_id], :hashed_password => params[:api_key]).first
         
       end
              
       acl = s.get_acl params[:opt], @current_user
       
       acl << 'user' if acl.size ==0
             
       # puts "#{params[:opt]} #{acl} #{@context.user} #{@current_user} #{acl.index('*')} #{@current_role!=nil}" 
       if  acl.index('*')!=nil or (@current_user and (@context.user == @current_user or acl.index 'user' or (@current_role!=nil and acl.index( @current_role)) ))
         @project_instance = @current_project.get_instance
         
         context = s.prepare(params,self,request)
                  obj = s.load context 
                  @current_object = obj
                  out = obj.send params[:opt], params
         #          #out = ''
       else
          session[:return_to]=request.fullpath
          render :text=>'<br/><br/><center>You are not authorized to use this service!!<br/><br/><a href="/user/login">Click to Login</a> | <a href="/user/logout">Reset session</a></center><br/>'
       end
       
      rescue Exception => e  
        
msg = <<MSG
#{DOMAIN}:#{request.fullpath}:#{Time.now.to_s};
#{e.message}
#{e.backtrace[0..10].join("\n")}
MSG

@msg = msg

puts "ERROR : #{Time.now.to_s} #{e.message}" 
puts request.fullpath 
puts e.backtrace[0..10].join("\n")

          msg_report DOMAIN+' Error : '+request.fullpath ,msg
          # render :text=> "Error" 
         render :file =>'public/500.html',:layout=>nil,:locals=>{:msg=>msg}
         return
         
      end 
       
    else
      render :text=>'Not found service on server'  
    end
       
     end
end

def home
  if params[:solution_name] and params[:project_name]
    redirect_to "/#{params[:solution_name]}/#{params[:project_name]}/Home/index"
  else
    
  end
  
end

def access
    s = nil
    @mode = :app
 
    
    path = "#{params[:solution_name]}.#{params[:project_name]}.#{params[:service]}"
    if params[:service]
       s = Service.get(path) 
    end
  
    if s
       
       begin 
       
       @current_service = s
       @current_project = s.project
       @current_solution = @current_project.esm
       @context = @current_solution
       opt = s.operations.find_by_name params[:opt]
       @current_role = nil
       
       if true
       
       if @current_user
         @current_role = Role.new :name=>'user'
       if @current_user.esm_id == @context.id
          @current_role = Role.new :name=>'member'
        end
       end
              
       acl = s.get_acl params[:opt], @current_user
             
       
       if @context.user == @current_user or acl.index '*' or ( @current_role and acl.index( @current_role.name))
         @project_instance = @current_project.get_instance
         context = s.prepare(params,self,request)
         obj = s.load context
         @current_object = obj
         out = obj.send params[:opt], params
       else
          session[:return_to]=request.fullpath
          render :text=>'<br/><br/><center>You are not authorized to use this service!!<br/><br/><a href="/user/login">Click to Login</a></center><br/>' +params.inspect
       end
       
     else
       render :file =>'public/404.html',:layout=>nil
       
     end
       
      rescue Exception => e  
        
msg = <<MSG
#{DOMAIN}:#{request.fullpath}:#{Time.now.to_s};
#{e.message}
#{e.backtrace[0..10].join("\n")}
MSG

puts "ERROR : #{Time.now.to_s}"
puts request.fullpath 
puts e.backtrace[0..10].join("\n")

@msg = msg

          msg_report DOMAIN+' Error : '+request.fullpath ,msg
          # render :text=> "Error" 
         render :file =>'public/500.html',:layout=>nil
         
      end 
       
    else
      render :text=>'Not found service on server '+path  
    end
       
end


def ws
  s = nil
  
  @mode = :app
  
  if params[:service]
     @current_project = Project.find_by_domain request.domain
     s = Service.get("#{@current_project.package}.#{params[:service]}") 
  else
     s = Service.get(params[:package].split('/').join('.')) 
     @current_project = s.project
     
  end
  
  if s
     obj = s.load
     s.prepare(params,self,request)
     
     out = obj.send params[:opt],params

  else
    render :text=>'Not found server'  
  end
end

 
end
