# require_relative 'esm'
# YAML::ENGINE.yamler='psych'
# jabber msg report func
def msg_report subject, body=nil
  require 'xmpp4r'
  # include Jabber
  begin
    
  unless body
  body=subject 
  subject = DOMAIN
  end
 
  jid = Jabber::JID::new( ESM_MSG_USER );
  password = ESM_MSG_PASS
  cl = Jabber::Client::new(jid)
  cl.connect( 'server.esm-solution.com' )
  cl.auth( password )

  to = 'soup@server.esm-solution.com'
  subject = subject
  body = ">#{body}"
  m = Jabber::Message::new( to, body ).set_type(:chat).set_id('1').set_subject(subject)
  cl.send m
  
 rescue
 end
  
end


# Include hook code here
# require File.dirname(__FILE__)+"/config"
require 'esm_essential'
require 'esm_scaffold'
@theme = 'default'
@theme = THEME if defined? THEME

# config.middleware.insert_before ::Rack::Lock, ::ActionDispatch::Static, "#{RAILS_ROOT}/public" 
# config.middleware.insert_before ::Rack::Lock, ::ActionDispatch::Static, "#{root}/public"
# config.middleware.insert_before ::Rack::Lock, ::ActionDispatch::Static, "#{root}/themes/#{@theme}/public"
# 
# 
# require 'activesupport' unless defined? ActiveSupport
# 
# if Rails.env == 'development'
#     
#     ActiveSupport::Dependencies.autoload_once_paths.delete root
#     ActiveSupport::Dependencies.autoload_once_paths.delete File.join(root, 'app','models','field.rb')
#     ActiveSupport::Dependencies.autoload_paths << root
#     ActiveSupport::Dependencies.autoload_paths << File.join(root, 'app','models', 'field.rb')
#     # ActiveSupport::Dependencies.autoload_paths
#     # ActiveSupport::Dependencies.autoload_once_paths
# end

