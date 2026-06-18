class EsmSeeds < ActiveRecord::Migration
  def up
          
command = <<EOF          
this = self
<%=command%>
EOF
          ScriptTemplate.create :name=>'ServiceTemplate',:generator=>command


command = <<EOF          
com=<<-HTML
<%=command%>
HTML
return render_template(com,self,params,true)
EOF
         ScriptTemplate.create :name=>'HTMLTemplate',:generator=>command

command = <<EOF          
com=<<-HTML
<%=command%>
HTML
return render_template(com,self,params)
EOF
        ScriptTemplate.create :name=>'PartialTemplate',:generator=>command

command = <<EOF          
com=<<-HTML
<%=command%>
HTML
return com
EOF
        ScriptTemplate.create :name=>'LayoutTemplate',:generator=>command

command = <<EOF          
this = self
com=<<-HTML
<%=command%>
HTML
return eval(com)
EOF
        ScriptTemplate.create :name=>'EvalTemplate',:generator=>command        


     
          role = Role.create :name=>'admin'
          user = User.create :login=>'admin',:role_id=>role.id,:password=>'minadadmin',:password_confirmation=>'minadadmin',:email=>'support@esm.co.th'

          esm = user.esms.create :name=>'system'
        
          
          # dashboard = esm.menu_actions.create :name=>'dashboard',:url=>'.'
          #          database = esm.menu_actions.create :name=>'database',:url=>'.'
          #          system = esm.menu_actions.create :name=>'system',:url=>'.'
          #    
          #          esm.menu_actions.create :name=>'actions',:url=>'/manage/menu_actions',:parent_id=>system.id
          #          esm.menu_actions.create :name=>'users',:url=>'/manage/users',:parent_id=>system.id
          #          esm.menu_actions.create :name=>'roles',:url=>'/manage/roles',:parent_id=>system.id
          #          esm.menu_actions.create :name=>'permissions',:url=>'/permissions',:parent_id=>system.id
          #          esm.menu_actions.create :name=>'logs',:url=>'/manage/logs',:parent_id=>system.id
          #          esm.menu_actions.create :name=>'esms',:url=>'/manage/esms',:parent_id=>system.id
          #          
          #          esm.menu_actions.create :name=>'projects',:url=>'/manage/projects',:parent_id=>database.id
          #          esm.menu_actions.create :name=>'services',:url=>'/manage/services',:parent_id=>database.id
          #          esm.menu_actions.create :name=>'operations',:url=>'/manage/operations',:parent_id=>database.id
          #          esm.menu_actions.create :name=>'script_templates',:url=>'/manage/script_templates',:parent_id=>database.id
          #          esm.menu_actions.create :name=>'settings',:url=>'/manage/settings',:parent_id=>database.id
          
          
 
                
  end

  def down
  end
end
