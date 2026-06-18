class EsmSuperClass 
attr_accessor :params,:view
def initialize
    
end

def context
        @params[:context]
end

def params
        @params
end

def render_template command, this, params,layout=false
        @view = ActionView::Base.new('vendor/plugins/esm_essential/app/views')
        @view.extend ActionView::Helpers
        @view.extend ApplicationHelper
        def @view.protect_against_forgery?
        return false
        end
        
        if layout
                command = "<% content_for :content do %>\n  \#{command} \n <% end %> \#{self.layout} "
        end
        puts command
        return @view.render(:inline=>command,:locals=>{:command=>command,:this=>this,:params =>params[0]})
end

def layout
        return '<%=yield :content%>'  
end


end