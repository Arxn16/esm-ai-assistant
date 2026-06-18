class ProjectsController < EsmAdminController
 
 esm_scaffold :project do |config|
         config[:fields][:esm_id]={:type=>:select,:list=>Esm.all.collect{|i|[i.name,i.id]}}
 end
 
end
