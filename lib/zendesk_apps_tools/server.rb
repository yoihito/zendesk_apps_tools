require 'sinatra/base'
require 'sinatra/cross_origin'
require 'zendesk_apps_support/package'

module ZendeskAppsTools
  class Server < Sinatra::Base
    register Sinatra::CrossOrigin

    set :public_folder, Proc.new {"#{settings.root}/assets"}
    set :allow_origin, :any

    get '/app.js' do
      content_type 'text/javascript'
      ZendeskAppsSupport::Package.new(settings.root).readified_js(nil, 0, "http://localhost:#{settings.port}/", settings.parameters)
    end

    def static!
      cross_origin
      super
    end

  end
end
