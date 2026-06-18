class AccountsController < EsmAdminController
 
 esm_scaffold :account do |config|
  # config[:columns]=%w{id login email last_accessed activate role_id}
  # show edit delete
  
  # config[:list][:actions]=[{:type=>:member,:name=>'Permissions',:url=>"/roles/\#{id}/permissions"}]
  # config[:fields][:esm_id]={:type=>:select,:list=>Esm.all.collect{|i|[i.name,i.id]}}
  #  config[:fields][:user_id]={:type=>:select,:list=>User.all.collect{|i|[i.login,i.id]}}
  #  roles = []
  #  Role.all.each{|r| roles+=["#{r.project.esm.name} - #{r.name}",r.id]}
  #  config[:fields][:role_id]={:type=>:select,:list=>roles}
  
  # 
  # 
 end
 
end
