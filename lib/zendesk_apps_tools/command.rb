require "thor"
require 'zip/zip'
require 'pathname'
require 'net/http'
require 'json'
require 'faraday'
require 'io/console'
require 'os'

require 'zendesk_apps_tools/command_helpers'
require 'zendesk_apps_tools/self_signed_certificate'

module ZendeskAppsTools

  require 'zendesk_apps_support'

  class Command < Thor

    SHARED_OPTIONS = {
      ['path', '-p'] => './',
      clean: false
    }

    include Thor::Actions
    include ZendeskAppsSupport
    include ZendeskAppsTools::CommandHelpers

    source_root File.expand_path(File.join(File.dirname(__FILE__), "../.."))

    desc 'translate SUBCOMMAND', 'Manage translation files', hide: true
    subcommand 'translate', Translate

    desc "new", "Generate a new app"
    def new
      @author_name  = get_value_from_stdin("Enter this app author's name:\n", error_msg: "Invalid name, try again:")
      @author_email = get_value_from_stdin("Enter this app author's email:\n", valid_regex: /^.+@.+\..+$/, error_msg: "Invalid email, try again:")
      @author_url   = get_value_from_stdin("Enter this app author's url:\n", valid_regex: /^https?:\/\/.+$/, error_msg: "Invalid url, try again:", allow_empty: true)
      @app_name     = get_value_from_stdin("Enter a name for this new app:\n", error_msg: "Invalid app name, try again:")

      get_new_app_directory

      directory('app_template', @app_dir)
    end

    desc "validate", "Validate your app"
    method_options SHARED_OPTIONS
    def validate
      setup_path(options[:path])
      errors = app_package.validate
      valid = errors.none?

      if valid
        app_package.warnings.each { |w| say w.to_s, :yellow }
        say_status 'validate', 'OK'
      else
        errors.each do |e|
          say_status 'validate', e.to_s
        end
      end

      @destination_stack.pop if options[:path]
      exit 1 unless valid
      true
    end

    desc "package", "Package your app"
    method_options SHARED_OPTIONS
    def package
      return false unless invoke(:validate, [])

      setup_path(options[:path])
      archive_path = File.join(tmp_dir, "app-#{Time.now.strftime('%Y%m%d%H%M%S')}.zip")

      archive_rel_path = relative_to_original_destination_root(archive_path)

      zip archive_path

      say_status "package", "created at #{archive_rel_path}"
      true
    end

    desc "clean", "Remove app packages in temp folder"
    method_option :path, default: './', required: false, aliases: "-p"
    def clean
      setup_path(options[:path])

      return unless File.exists?(Pathname.new(File.join(app_dir, "tmp")).to_s)

      FileUtils.rm(Dir["#{tmp_dir}/app-*.zip"])
    end

    DEFAULT_SERVER_PATH = "./"
    DEFAULT_CONFIG_PATH = "./settings.yml"
    DEFAULT_SERVER_PORT = 4567

    desc "server", "Run a http server to serve the local app"
    method_option :path, default: DEFAULT_SERVER_PATH, required: false, aliases: "-p"
    method_option :config, default: DEFAULT_CONFIG_PATH, required: false, aliases: "-c"
    method_option :port, default: DEFAULT_SERVER_PORT, required: false
    method_option :ssl, required: false, type: :boolean, desc: "Enable SSL"
    method_option :ssl_cert, required: false, desc: "Path to SSL certificate file"
    method_option :ssl_key, required: false, desc: "Path to SSL private key file"
    def server
      ssl_certificate = options[:ssl_cert]
      ssl_key = options[:ssl_key]

      if (options[:ssl_cert] && !options[:ssl_key]) || (!options[:ssl_cert] && options[:ssl_key])
        raise ArgumentError.new("Either both --ssl-key and --ssl-cert options should be specified or neither")
      end

      if options[:ssl] && !ssl_certificate && !ssl_key
        unless File.exists?(localhost_ssl_cert_path) && File.exists?(localhost_ssl_key_path)
          generate_and_trust_certificate
        end
        ssl_certificate = localhost_ssl_cert_path.to_s
        ssl_key = localhost_ssl_key_path.to_s
      end

      setup_path(options[:path])
      manifest = app_package.manifest_json

      settings_helper = ZendeskAppsTools::Settings.new

      settings = settings_helper.get_settings_from_file options[:config], manifest[:parameters]

      unless settings
        settings = settings_helper.get_settings_from_user_input self, manifest[:parameters]
      end

      require 'zendesk_apps_tools/server'
      ZendeskAppsTools::Server.tap do |server|
        server.set :port, options[:port]
        server.set :root, options[:path]
        server.set :parameters, settings
        server.set :server, 'thin'
        server.run! do |server|
          if options[:ssl] != false && ssl_certificate && ssl_key
            server.ssl = true
            server.ssl_options = {
              :cert_chain_file => ssl_certificate,
              :private_key_file => ssl_key,
              :verify_peer => false
            }
          end
          EM.next_tick do
            if server.ssl?
              zat_url = "https://localhost:#{server.port}/app.js"
            elsif server.port != DEFAULT_SERVER_PORT
              zat_url = "http://localhost:#{server.port}/app.js"
            else
              zat_url = 'true'
            end
            puts "== ZAT Server is running"
            puts "You may now start using ZAT by appending ?zat=#{zat_url} to your Zendesk URL"
          end
        end
      end
    end

    desc "create", "Create app on your account"
    method_options SHARED_OPTIONS
    method_option :zipfile, default: nil, required: false, type: :string
    def create
      clear_cache
      @command = 'Create'

      unless options[:zipfile]
        app_name = JSON.parse(File.read(File.join options[:path], 'manifest.json'))['name']
      end
      app_name ||= get_value_from_stdin('Enter app name:')
      deploy_app(:post, '/api/v2/apps.json', { name: app_name })
    end

    desc "update", "Update app on the server"
    method_options SHARED_OPTIONS
    method_option :zipfile, default: nil, required: false, type: :string
    def update
      clear_cache
      @command = 'Update'

      app_id = get_cache('app_id') || find_app_id
      unless /\d+/ =~ app_id.to_s
        say_error_and_exit "App id not found\nPlease try running command with --clean or check your internet connection"
      end
      deploy_app(:put, "/api/v2/apps/#{app_id}.json", {})
    end

    protected

    def setup_path(path)
      @destination_stack << relative_to_original_destination_root(path) unless @destination_stack.last == path
    end

    def config_dir
      @config_dir ||= begin
        if OS.mac?
          File.join(Dir.home, 'Library/Application Support/ZAT')
        elsif OS.windows?
          File.join(ENV['APPDATA'] || Dir.home, 'ZAT')
        elsif ENV['XDG_CONFIG_HOME']
          File.join(ENV['XDG_CONFIG_HOME'], 'zat')
        else
          File.join(Dir.home, '.zat')
        end
      end
      Dir.mkdir @config_dir unless Dir.exists? @config_dir
      @config_dir
    end

    def localhost_ssl_cert_path
      File.join(config_dir, 'localhost.pem')
    end

    def localhost_ssl_key_path
      File.join(config_dir, 'localhost.key')
    end

    def generate_certificate
      puts "Generating certificate..."
      certificate = SelfSignedCertificate.new
      File.write(localhost_ssl_cert_path, certificate.self_signed_pem)
      File.write(localhost_ssl_key_path, certificate.private_key)
    end

    def trust_certificate
      if OS.mac?
        puts "Trusting certificate..."
        exec_cmd("sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \"#{localhost_ssl_cert_path}\"")
      elsif OS.windows? && executable_exists?('certutil.exe')
        puts "Trusting certificate..."
        exec_cmd("certutil.exe -addstore -user root \"#{localhost_ssl_cert_path}\"")
      elsif executable_exists?('certutil') && File.exists?("#{ENV["HOME"]}/.pki/nssdb")
        puts "Trusting certificate..."
        exec_cmd("certutil -A -d sql:$HOME/.pki/nssdb -t C -n localhost -i \"#{localhost_ssl_cert_path}\"")
      else
        puts "Open \"#{localhost_ssl_cert_path}\" and add it to your trusted certificate store to bypass any SSL warnings"
      end
    end

    def exec_cmd(cmd)
      puts "> #{cmd}"
      system(cmd)
    end

    def generate_and_trust_certificate
      generate_certificate
      trust_certificate
    end

    def executable_exists?(cmd)
      ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
        exe = File.join(path, cmd)
        return exe if File.executable?(exe) && !File.directory?(exe)
      end
    end

  end
end
