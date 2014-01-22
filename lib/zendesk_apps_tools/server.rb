require 'sinatra/base'
require 'zendesk_apps_support/package'

require 'webrick'
require 'webrick/https'
require 'openssl'

module ZendeskAppsTools
  WEBRICK_OPTIONS = {
    :Logger          => WEBrick::Log::new($stderr, WEBrick::Log::DEBUG),
    :SSLEnable       => true,
    :SSLVerifyClient => OpenSSL::SSL::VERIFY_NONE,
    :SSLPrivateKey   => OpenSSL::PKey::RSA.new(File.open(File.expand_path('~/.zat/zat.key')).read),
    :SSLCertificate  => OpenSSL::X509::Certificate.new(File.open(File.expand_path('~/.zat/zat.crt')).read),
    :SSLCertName     => [ [ 'CN', WEBrick::Utils::getservername ] ]
  }

  class Server < Sinatra::Base
    set :public_folder, Proc.new {"#{settings.root}/assets"}

    get '/app.js' do
      content_type 'text/javascript'
      ZendeskAppsSupport::Package.new(settings.root).readified_js(nil, 0, "http://localhost:#{settings.port}/", settings.parameters)
    end
  end
end
