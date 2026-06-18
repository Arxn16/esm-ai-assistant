class RolesController < EsmAdminController
 
 esm_scaffold :role do |config|
  # config[:columns]=%w{id login email last_accessed activate role_id}
  # show edit delete
  
  config[:list][:actions]=[{:type=>:member,:name=>'Permissions',:url=>"/roles/\#{id}/permissions"}]
  config[:fields][:esm_id]={:type=>:select,:list=>Esm.all.collect{|i|[i.name,i.id]}}
  
  
 end
 
end
