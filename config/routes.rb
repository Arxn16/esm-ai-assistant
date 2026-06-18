require 'resque/server'
Esmx::Application.routes.draw do
  
  
    mount Resque::Server.new, :at => "/resque"
    
    
    

         # AI Assistant (global floating widget) placeholder endpoint.
         # Declared before the generic ':controller/:id' catch-alls below or the
         # POST would be hijacked to AiAssistantController#show (id='message').
         match 'ai_assistant/message'=>'ai_assistant#message' ,via: [:post]

         match 'home/:action'=>'home', via: [:get, :post]

         resources :esms
         resources :menu_actions
         resources :settings
         resources :users
         resources :roles
         resources :permissions
         resources :logs
         resources :projects
         resources :services
         resources :operations
         resources :script_templates

         # match 'esm/:esm/:project/:service/:opt' =>'esm_proxy#index'
         get 'barcode' =>'esm_image#barcode'
         match 'content/esm/*package/:id(.:format)'=>'esm_attachments#show' ,via: [:get, :post]
         match 'content/data/*package/:id/:filename(.:format)'=>'esm_attachments#show' ,via: [:get, :post]
         
         # match 'content/esm/:solution_name/:project_name/*package/:id(.:format)'=>'esm_attachments#show' ,via: [:get, :post]


         match 'esm/*package/:opt' =>'esm_proxy#index' ,via: [:get, :post]


         match 'user'=>'user#index' ,via: [:get, :post]
         match 'user/:action'=>'user' ,via: [:get, :post]
         match 'elfinder' => 'esm_content#elfinder' ,via: [:get, :post]

         match 'manage/:model'=>'manage#index' ,via: [:get, :post]
         post  'manage/:model'=>'manage#create' 
         match 'manage/:model/new'=>'manage#new' ,via: [:get, :post]
         match 'manage/:model/create'=>'manage#create',via: [:get, :post]
         match 'manage/:model/:id'=>'manage#show' ,via: [:get, :post]
         post  'manage/:model/:id'=>'manage#update'
         put   'manage/:model/:id'=>'manage#update'
         delete 'manage/:model/:id'=>'manage#destroy'
         match  'manage/:model/destroy/:id'=>'manage#destroy' ,via: [:get, :post]
         match  'manage/:model/:id/:action'=>'manage' ,via: [:get, :post]

         match 'esm_home/:action'=>'esm_home' ,via: [:get, :post]
         match 'esm_home/:action/:id'=>'esm_home' ,via: [:get, :post]
         match 'esm_home'=>'esm_home#index' ,via: [:get, :post]

         match 'esm_content/:id'=>'esm_content#show' ,via: [:get, :post]
         match 'esm_content/:id/:action'=>'esm_content' ,via: [:get, :post]


         match 's/:service/:opt' =>'esm_proxy#index' ,via: [:get, :post]
         match 's/:service' =>'esm_proxy#index', :opt=>'index' ,via: [:get, :post]

         match 'ws/:service/:opt' =>'esm_proxy#ws' ,via: [:get, :post]
         match 'ws/:service' =>'esm_proxy#ws', :opt=>'index' ,via: [:get, :post]

         match 'admin/:id'=>'admin#show' ,via: [:get, :post]
         match 'admin/:id/:action'=>'admin' ,via: [:get, :post]



         match ':controller', :action=>'index' ,via: [:get, :post]
         match ':controller/new',:action=>'new' ,via: [:get, :post]
         post  ':controller/create',:action=>'create'

         match ':controller/destroy/:id',:action=>'destroy' ,via: [:get, :post]
         match ':controller/:id',:action=>'show' ,via: [:get, :post]
         match ':controller/:id/:action' ,via: [:get, :post, :patch]

         match ':solution_name/:project_name/:service/:opt'=>'esm_proxy#index' ,via: [:get, :post,:delete, :put]
         
         match ':solution_name/:project_name/:service/*id/:opt'=>'esm_proxy#index' ,via: [:get, :post,:delete, :put]
         
         # match ':solution_name/:project_name/:service/*id'=>'esm_proxy#index' ,via: [:get, :post,:delete, :put]
         
         
         
         match ':solution_name/:project_name'=>'esm_proxy#home',via: [:get, :post]

         match ':project_name/:service/:opt'=>'esm_proxy#index',via: [:get, :post,:delete, :put]
         match ':project_name/:service/:opt'=>'esm_proxy#index',via: [:get, :post,:delete, :put], :constraints => lambda { |req| req.format == :json }
         match ':project_name/:service/:opt'=>'esm_proxy#index',via: [:get, :post,:delete, :put], :constraints => lambda { |req| req.format == :shtml }
         
         

         # match ':project_name'=>'esm_proxy#home'

         match ':content'=>'home#content' ,via: [:get, :post]


    root :to => "home#index"
    match ':controller(/:action(/:id(.:format)))' ,via: [:get, :post]
    
  # The priority is based upon order of creation:
  # first created -> highest priority.

  # Sample of regular route:
  #   match 'products/:id' => 'catalog#view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  #   match 'products/:id/purchase' => 'catalog#purchase', :as => :purchase
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Sample resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Sample resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Sample resource route with more complex sub-resources
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', :on => :collection
  #     end
  #   end

  # Sample resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end

  # You can have the root of your site routed with "root"
  # just remember to delete public/index.html.
  # root :to => 'welcome#index'

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id))(.:format)'
end
