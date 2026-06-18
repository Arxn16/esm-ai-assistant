class EsmAdminController < EsmController

  before_filter :login_admin_required
  
  def login_admin_required
    
    unless @current_user 
       redirect_to '/user/login'
       return 
    end
      
    if @current_user and @current_user.role=nil
        redirect_to '/user/login'
        return 
    end
    # redirect_to '/user/login'
    
  end
  
end