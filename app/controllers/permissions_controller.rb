class PermissionsController < EsmAdminController
 
 esm_scaffold :permission do |config|
    config[:columns]=%w{role_id menu_action_id}
   
   list = Role.all.collect{|i| [i.name,i.id]}
   config[:fields][:role_id]={:type=>:select,:list=>list}
   list = MenuAction.all.collect{|i| [i.name,i.id]}
   config[:fields][:menu_action_id]={:type=>:select,:list=>list}
   
 end
 
end
