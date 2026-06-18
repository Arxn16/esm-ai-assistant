require 'basic_auth'
class EsmController < ApplicationController
    include BasicAuth
    # include ReCaptcha::AppHelper
    
  

    before_filter :context_filter
    def context_filter
           

          Time.zone =  'Bangkok'
          
          puts request.host
          select_esm = Esm.find_by_url request.host
          
          # direct url
          if select_esm
             params[:solution_name] = select_esm.name   
          elsif cookies[:esm]
             params[:solution_name] = cookies[:esm]  
          else
             subdomain = request.host.split('.')
             if !params[:solution_name] and subdomain[0]!=DOMAIN.split(".")[0] and subdomain[0]!='localhost' and subdomain[0]!='192' and subdomain[0].to_i==0
                     params[:solution_name] = subdomain[0]
             end  
                            
          end
          
          if params[:solution_name]
                  @solution_mode = true 
                  @current_solution = Esm.find_by_name params[:solution_name]  
                  unless  @current_solution
                    @current_solution = Esm.find_by_name params[:solution_name].gsub('-','_') 
                    params[:solution_name] =params[:solution_name].gsub('-','_') 
                  end
                  
                  if @current_solution
                  www = @current_solution.get_www
                  @user_model = www.get_model 'user'
                  
                  end
                  
                   if params[:project_name]
                           @current_project = @current_solution.projects.find_by_name params[:project_name]
                   else
                           @current_project = @current_solution.projects.find_by_name 'www'
                   end
          end
                   
          
             
          if session[:user]
           
            if session[:user].to_s.size<10
                @current_user = User.find(session[:user]) 
                
                if session[:esm]    
                @current_solution = Esm.find session[:esm]
                else
                @current_solution = Esm.find_by_name params[:solution_name] 
                end
                @current_role = Role.new(:name=>'user').name
                
                @current_role = 'developer' if @current_solution and @current_solution.user == @current_user
                
            elsif session[:esm]
        
                @current_solution = Esm.find session[:esm]
                @current_user, @current_role , @solution_user =  @current_solution.get_user_role_by_id session[:user].to_s
                session[:solution_user] = @solution_user
                @solution_user = true
       
            end
            
            if @current_user
              if params[:controller]!='logs' and params[:controller]!='esm_attachments'
                # Log.create :user_id=>@current_user.id,:role_id=>@current_user.role_id,:remote_ip=>request.remote_ip,:path=>request.fullpath
              end   
            end
           
           
            # rescue 
            # end
          end
     
  
          unauthorize= false
          
          if params[:solution_name] 
            @current_solution = Esm.find_by_name params[:solution_name]
            if @current_solution
              if params[:project_name]
                @current_project = @current_solution.projects.find_by_name params[:project_name]
              else
                @current_project = @current_solution.projects.find_by_name 'www'
              end
            else
              unauthorize =true
            end
          end
          
          if @current_user
            unless @current_solution
              if session[:esm]
                
                begin
                @current_solution =Esm.find(session[:esm]) 
                rescue
                  @current_solution = nil
                  session[:esm]= nil
                end
                
              else
                
                  l = @current_user.my_solutions
                  # puts 'xxxxxxxxx'
                  # puts l.inspect
                  if l.size>0
                  @current_solution = l[0]
                  
                  if @current_solution
                    @current_project = @current_solution.projects.find_by_name 'www'
                    session[:esm] = @current_solution.id if @context
                  end
                end
              end
            end
          end
          
          unless unauthorize
          
          @context = @current_solution
          @current_theme = 'default'
          @current_theme = THEME if defined? THEME
          @theme_path = File.join('esm','themes',@current_theme)
          
          else
            # redirect_to "/user/login"
          end
          
          
                       
    end
    
    def render_to_panel *p
      render :partial=>'/esm/render_to_panel.html',:locals=>{:p=>p}
    end
    
    def change_screen_size
       session[:screen] = params[:screen]
       redirect_to params[:return]
    end
  
    
  
  
end
