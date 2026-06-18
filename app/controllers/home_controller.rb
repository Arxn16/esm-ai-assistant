class HomeController < EsmController
  
  # before_filter :login_required
  
  def index
    
    @home = Service.find_by_package 'admin.www.Home'
    @operation = @home.operations.find_by_name 'index'
    unless @current_user
    if @solution_mode
      
      # check weather www/Home/index is *
      
      www = @current_solution.projects.find_by_name 'www'
      www.get_instance
      
      home_acc = false
      msg = "no"
      
      if www
      
      home = www.get_service 'home'
      
      if home
        
      index_op = home.operations.find_by_name 'index'
      
      if index_op and index_op.acl.strip == '*'
        
        home_acc = true
        redirect_to "/www/Home/index"
        
      else
        msg = "no_opt"
      end
      
      else
        msg = "no_home"
      
      end
      
      else
      msg = "no_www"

      end
      
      unless home_acc
      
      redirect_to "/user/login?msg=#{msg}"
    
      end
    
    
    else
      render :action=>'index'
    end
    else
      if @current_solution
        redirect_to @current_solution.default_home request
      end
    end
    
  end

  
  def content

           m = params[:content]
          
      @home = Service.find_by_package 'admin.www.Home'
      @operation = @home.operations.find_by_name m
      if @operation
        render :action=>'index'
      else
        if @current_solution 
          project = @current_solution.projects.find_by_name m
          if project   
            redirect_to project.get_home_url request 
          else
            render :text=>('File Not Found 1'+ @current_solution.name + "  #{session[:esm]} #{params.inspect }")
          end
        else
          solution = Esm.find_by_name m
          if solution 
            redirect_to solution.get_home_url request
          else
            render :text=>'File Not Found 2'
          end
        end
      end
  end
  
  
  def  test
    #
    # @current_solution = Esm.find_by_name 'cusys'
    #
    # s = @current_solution.projects.find_by_name 'colorectal'
    #
    # s.get_instance
    #
    # home = s.get_service 'home'
    #
    # render :text=>home.operations.find_by_name('index').command
  end
  
    # 
    # def show
    #   pdf = WickedPdf.new.pdf_from_string('<h1>Hello There!<%=Time.now%></h1>content<span style="page-break-after:always">&nbsp;</span> Other content',:footer=>{:content=>Time.now.to_s})
    #   render :text=>pdf,:content_type=>'application/pdf'
    #  end
    #  
    # def test
    #   @command = '<%=Time.now %>'
    #   render :action=>'test'
    # end

end
