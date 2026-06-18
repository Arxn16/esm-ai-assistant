require 'pdfkit'
require 'net/http'

class PdfGenerator < Task
  
  def self.perform(params)
  
      puts "Pdf Generator #{Esm.count}"
      puts params.inspect 
      if params['url']
      # url = "https://#{DOMAIN}/#{@current_solution.name}/#{@current_project.name}/#{@current_service.name}/pdf?id=#{@patient_module.id}"
      # patient_module  = models[:patient_module]
      #    
      # @patient_module = patient_module.find(params[:patient_module_id])  
      # file = "tmp/cache/#{@patient_module.id.to_s}.pdf"
      id = 'id'
      id = params['id'] if params['id']  
      path = 'pdf'
      path = params['path'] if params['path']
      pdf_file = File.join("tmp","cache","#{path}.#{id}.pdf")
      url = params['url']
      puts 'start'
      kit = PDFKit.new(url,:margin_top => '0.2in',:margin_right => '0.2in',:margin_bottom => '0.2in',:javascript_delay => 1000)
      file = kit.to_file(pdf_file)
      puts 'finish'
      
      return_url = nil
      return_url = params['return'] if params['return']
    
      if return_url
          # uri = URI(return_url)
           # result = Net::HTTP.get(uri)
          return_url += "&path=#{pdf_file}"
          puts return_url
          result = `curl --insecure '#{return_url}'`
          puts "result of return : #{result.strip}"
      end
      
      puts 'finish'
      
    end
      
      
  end

end