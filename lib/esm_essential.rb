# EsmEssential
require 'basic_auth'

%w{ models controllers helpers views }.each do |dir|
  path = File.join(File.dirname(__FILE__), '..','app', dir)
    $LOAD_PATH << path
    ActiveSupport::Dependencies.autoload_paths << path
    ActiveSupport::Dependencies.autoload_once_paths.delete(path)
  end
  
  
  path = File.join(File.dirname(__FILE__), '..','themes','default','views')
  $LOAD_PATH << path
  ActiveSupport::Dependencies.autoload_paths << path
  ActiveSupport::Dependencies.autoload_once_paths.delete(path)
  
  

ActiveSupport::Dependencies.autoload_paths << File.dirname(__FILE__)
ActiveSupport::Dependencies.autoload_once_paths.delete(File.dirname(__FILE__))