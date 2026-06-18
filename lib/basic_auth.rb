module BasicAuth

  def login_required
          
          
    if params[:package]
            
      # puts "with package #{params[:package]}"
     params[:solution_name] = params[:package].split("/")[0]
    end
        
    # subdomain = request.host.split('.')
    # if subdomain[0]!=DOMAIN.split(".")[0] and subdomain[0]!='localhost' and subdomain[0]!='192' 
    # 
    #         
    #    params[:solution_name] = subdomain[0]
    #    # puts "with sub domain #{params[:solution_name]}"
    #    
    #    @solution_mode = true 
    # end
    
    
        Time.zone =  'Bangkok'
        
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
             
       @current_solution = Esm.find_by_name params[:solution_name]    
       if @current_solution 
       # puts "with solution name #{params[:solution_name]}"
       www = @current_solution.get_www
       # puts "zz #{www.get_instance.inspect}"
       @user_model = www.get_model 'user'
       # puts "yyy #{list.inspect}"
       
       end
    end           
          
    if session[:user]
      return true
    end
    flash[:warning]='Please login to continue'
    session[:return_to]=request.fullpath
    redirect_to :controller => "user", :action => "login"
    return false 
  end

  def current_user
    session[:user]
  end
  
  def redirect_to_stored
    if return_to = session[:return_to]
      session[:return_to]=nil
       redirect_to url_for(return_to)
    else
      redirect_to :controller=>'user', :action=>'welcome'
    end
  end  

end
