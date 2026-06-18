require 'resque'

module Job
  
class JobTest
    
    @queue = :job

    def self.perform(pp)
   
      app = ActionDispatch::Integration::Session.new(Rails.application)
      params = nil
      
      url = "/esm/#{pp[0].split(".").join("/")}/#{pp[1]}"
      
      if pp[2]
        url+="?"
        pp[2].each_pair do |k,v|
          url+="#{k}=#{v}"
        end
      end
      
      app.get URI.escape(url)
      content = app.response.body 
      
     puts content
     
   end
end

end
