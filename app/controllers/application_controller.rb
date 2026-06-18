class ApplicationController < ActionController::Base
  protect_from_forgery
  
  # force_ssl :except => [:index,:content]
  
end
