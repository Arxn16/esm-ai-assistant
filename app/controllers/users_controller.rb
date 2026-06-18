class UsersController < EsmAdminController
 
 esm_scaffold :user do |config|
  config[:columns]=%w{id login role_id activate  password password_confirmation email last_accessed  salt}
  config[:fields][:password]={:type=>:password_field}
  config[:fields][:password_confirmation]={:type=>:password_field}
  config[:fields][:role_id]={:type=>:select,:list=>Role.all.collect{|i|[i.name,i.id]}}
  config[:list][:columns] = %w{id login role_id activate email last_accessed salt }
  config[:edit][:columns] = %w{login role_id activate email} 
  config[:new][:columns] = %w{login  role_id activate password password_confirmation email} 
  config[:fields][:esm_id]={:type=>:select,:list=>Esm.all.collect{|i|[i.name,i.id]}}
  
 end
 
end
