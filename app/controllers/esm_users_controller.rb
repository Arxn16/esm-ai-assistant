class EsmUsersController < EsmController

  before_filter :login_required
  
  layout 'esm_application'
  
  before_filter :workspace
  
  def workspace urls = nil
    
     @url = url_for urls
      params[:update]='workspace' unless params[:update]
  end
  
  def index
    @users = User.all.to_a
  end
  
  def refresh
    @project = Project.find(params[:id])
    @context = @project.esm
    @current_project = @project
    render_to_panel :partial=>'show'
  end
  
  def show
      
        @user = User.find(params[:id])
       
       
        respond_to do |format|
          format.html {render :show}
        end
        
  end
  
  def new
         @user = @context.users.new
         if request.post?
                 
                 params[:user][:login] = "#{params[:user][:login]}@#{@context.name}.#{DOMAIN}" unless params[:user][:login].index '@'
                 
                 @user.update_attributes params[:user]
                 if @user.save
                         redirect_to :controller=>'esm_home',:action=>'index'
                 end
         end
   end

   def edit
         @user = User.find(params[:id])
         if request.post?
                 @user.update_attributes params[:user]
                 if @user.save
                         redirect_to :controller=>'esm_home',:action=>'index'
                 end
         end
   end

   def destroy
         @user = User.find(params[:id])
         @user.destroy
         redirect_to :action=>'index'
   end

  
end