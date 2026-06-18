class UserController < EsmController
    
 
 
 before_filter :login_required, :only=>['welcome', 'change_password', 'hidden', 'logout' ]
 
 before_filter :context
 
 def context
   if params[:id] and params[:id]!=''
     @current_project = Project.find(params[:id]) 
   end
 end
 
 def index
  redirect_to '/home/index'
 end
 
  def signup
    @user = User.new(params[:user])
    if request.post?  
       @user.activate = true
     
      if  @user.save
       
        flash[:message] = "Signup successful"
        
        redirect_to :action=>'login'
        # session[:user] = User.authenticate(@user.login, @user.password)
        # redirect_to :action => "welcome"          
      else
        flash[:error] = "Signup unsuccessful"
      end
    else
      render :action=>'signup'
      
    end
  end
  
  
 def profile
    respond_to do |format|
        format.html { render 'profile',:layout=>'application' }
    end
 end
 

 
  def login
     
    esm = nil
   
    if request.post? or cookies[:login]
      
      
      if  params[:user] and params[:user][:esm] and params[:user][:esm]!='' and esm = Esm.find_by_name(params[:user][:esm]) and params[:user][:login].index('@')==nil
              
           session[:esm] = esm.id
           login ="#{params[:user][:login]}@#{params[:user][:esm]}.#{DOMAIN}"
           
           if User.find_by_login login
                   params[:user][:login] = login
           end
           
           # cookies[:esm] = esm.name
       
           
           www = esm.get_www
           models = www.get_model         
           user_model = models[:user]
           user = user_model.where(:login=>params[:user][:login]).first
           
           if user and User.encrypt(params[:user][:password], user.salt) == user.hashed_password
                   # flash[:error] = "You are not authorized to access!!"
                   @user = user 
           end
                      
      else
           # cookies.delete :esm
      end
      

      if cookies[:login] 
        unless cookies[:esm]
                @user = User.find_by_hashed_password cookies[:login]
        else
                session[:user_type]='solution'
                esm = Esm.find_by_name(cookies[:esm])
                www = esm.get_www
                models = www.get_model
                user_model = models[:user]
                user = user_model.where(:hashed_password=>cookies[:login]).first
                @user = user
            
        end
      end
      
      
      if @user or (params[:user] and @user = User.authenticate(params[:user][:login], params[:user][:password]) )
         
        # msg_report "#{DOMAIN} login by #{@user.login}","#{DOMAIN} login by #{@user.login}"
      
         
         if params[:remember]
             unless params[:user][:esm]         
                     cookies[:login] = { :value => @user.hashed_password, :expires => Time.now + 3600*24*7}
                else
                     cookies[:login] = { :value => @user.hashed_password, :expires => Time.now + 3600*24*7}
                     cookies[:esm] = { :value => esm.name, :expires => Time.now + 3600*24*7}
                end
         end
         
         session[:user] = @user.id
         
         flash[:message] = "Login successful"
         
         # if define access return to path
         if session[:return_to]
              r = session[:return_to]
              session[:return_to]=nil
              redirect_to r
         # if define project id
         elsif params[:user] and params[:user][:project_id] 
           
            redirect_to Project.find(params[:user][:project_id]).get_home_url(request)
            
         # if define solution otherwise it will be default solution
         elsif params[:user] and params[:user][:esm] and params[:user][:esm]!=''
                 
          params[:solution_name] = params[:user][:esm]
                
           # puts "osijfisodjf #{Esm.find_by_name(params[:user][:esm]).projects.find_by_name('www').get_home_url(request)}"        
           redirect_to "#{Esm.find_by_name(params[:user][:esm]).projects.find_by_name('www').get_home_url(request)}"
           
         else
          if @user.kind_of? User and esm = @user.my_solutions.first
           redirect_to esm.default_home(request)
          elsif @current_solution
           redirect_to @current_solution.default_home(request)
          else
            redirect_to "/"      
          end
         end
         
      else
        flash[:error] = "Login unsuccessful"
        
      render_login
        
      end
    else
      render_login
    end
  end

  def logout
    
    logout_path = nil
    logout_path = session[:logout_path]
    
    
    session.clear                 
    session[:user] = nil
    session[:user_type] = nil
    session[:project] = nil
    session[:esm] = nil
    session[:return_to]=nil
    session[:solution_user]=nil
    session.delete :user
    session.delete :user_type
    session.delete :esm
    session.delete :return_to
    
    cookies.delete :login 
    cookies.delete :esm if params[:solution]
    flash[:message] = 'Logged out'
    flash[:logout_path] = logout_path
    if params[:redirect_to]
    redirect_to params[:redirect_to]
    elsif logout_path

    redirect_to logout_path
    
    else
      
    # redirect_to "/user/login?id=#{params[:id]}"
    
  redirect_to "/user/login"
    end
  end

  def forgot_password
    if request.post?
      u= User.find_by_email(params[:user][:email])
      if u and u.send_new_password
        flash[:message]  = "A new password has been sent by email."
        redirect_to :action=>'login'
      else
        flash[:warning]  = "Couldn't send password"
      end
    end
  end
  
  def change_password
    @user=User.find(session[:user])
    if request.post?
      @user.update_attributes(:password=>params[:user][:password], :password_confirmation => params[:user][:password_confirmation])
      if @user.save
        flash[:message]="Password Changed"
      end
      redirect_to :controller=>'home'
    end
  end

  def list
     @users = User.find(:all)
  end

  def welcome
  end
  def hidden
  end
  
  protected
  
  def render_login
          
          if @context
          
          www =  @context.get_www
          
          # @current_service = s
          #               @current_project = s.project
          #               @current_solution = @current_project.esm
          #               @context = @current_solution
          #               opt = s.operations.find_by_name params[:opt]
          #           
          #           service = www.get_service 'home'
          #           
           
          s = Service.get("#{@current_project.package}.Home") 
          @current_service = s
          @current_project = s.project
          @current_solution = @current_project.esm
          @context = @current_solution
          
          @project_instance = @current_project.get_instance
          context = s.prepare(params,self,request)
          obj = s.load context
          if obj.methods.index :login
                  out = obj.send 'login', params
                  # render :action=>'login' 
                  
                  render :inline=>out
          else
                  render :action=>'login' 
          end          
          else
                  render :action=>'login' 
          end
  end
  
end
