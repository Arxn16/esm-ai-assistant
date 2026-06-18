class MenuActionsController < EsmAdminController
 
        esm_scaffold :menu_action do |config|

          config[:fields][:parent_id]={:show=>'parent_id',:type=>:select,:list=>Esm.first.menu_actions.collect{|i|[i.name,i.id]}}
          config[:fields][:esm_id]={:type=>:select,:list=>Esm.all.collect{|i|[i.name,i.id]}}

        end
 
end
