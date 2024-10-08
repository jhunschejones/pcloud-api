module Pcloud
  module Client
    class ErrorResponse < StandardError; end
    class ConfigurationError < StandardError; end

    VALID_DATA_REGIONS = [
      EU_DATA_REGION = "EU".freeze,
      US_DATA_REGION = "US".freeze
    ].freeze
    US_API_BASE = "api.pcloud.com".freeze
    EU_API_BASE = "eapi.pcloud.com".freeze
    DEFAULT_TIMEOUT_SECONDS = 8.freeze

    class << self
      def configure(access_token: nil, data_region: nil, timeout_seconds: nil)
        @@access_token = access_token
        @@data_region = data_region
        @@timeout_seconds = timeout_seconds.nil? ? nil : timeout_seconds.to_i
        true # Don't accidentally return any secrets from the configure method
      end

      def execute(method, query: {}, body: {})
        verb = ["uploadfile"].include?(method) ? :post : :get
        options = {
          headers: { "Authorization" => "Bearer #{access_token_from_config_or_env}" },
          timeout: timeout_seconds_from_config_or_env # this sets both the open and read timeouts to the same value
        }
        options[:query] = query unless query.empty?
        options[:body] = body unless body.empty?
        response = HTTParty.public_send(verb, "https://#{closest_server}/#{method}", options)
        json_response = JSON.parse(response.body)
        raise ErrorResponse.new(json_response["error"]) if json_response["error"]
        json_response
      end

      def generate_access_token
        puts "=== Follow these steps to generate a pCloud app and access token ==="
        puts "1. Register an app at `https://docs.pcloud.com/my_apps/`"

        puts "2. Enter the client id and secret for the app:"
        print "Client ID > "
        client_id = $stdin.gets.chomp

        print "Client Secret > "
        client_secret = $stdin.gets.chomp

        puts "3. Enter the data region of your pCloud account [EU/US]:"
        print "> "
        region_specific_api_base = $stdin.gets.chomp == "EU" ? "eapi.pcloud.com" : "api.pcloud.com"

        puts "4. Navigate to this URL to start the access code flow:"
        puts "`https://my.pcloud.com/oauth2/authorize?client_id=#{client_id}&response_type=code`"
        puts "5. After logging in, enter the access code provided below:"
        print "> "
        access_code = $stdin.gets.chomp

        puts "6. Requesting access token from pCloud..."
        query = { client_id: client_id, client_secret: client_secret, code: access_code }
        response = HTTParty.post(
          "https://#{region_specific_api_base}/oauth2_token?#{URI.encode_www_form(query)}",
          headers: { "Accept" => "application/json" }
        )

        json_response = JSON.parse(response.body)
        raise json_response["error"] if json_response["error"]
        puts "Done! Your access token is: \n#{json_response["access_token"]}"
        puts "\nStore this value somewhere secure as it can be used to access your"
        puts "pCloud account data and it will not be shown again."
      end

      private

      def data_region_from_config_or_env
        @@data_region ||= ENV["PCLOUD_API_DATA_REGION"]
        return @@data_region if VALID_DATA_REGIONS.include?(@@data_region)
        raise ConfigurationError.new("Missing pCloud data region") if @@data_region.nil?
        raise ConfigurationError.new("Invalid pCloud data region, must be one of #{VALID_DATA_REGIONS}")
      end

      def access_token_from_config_or_env
        @@access_token ||= ENV["PCLOUD_API_ACCESS_TOKEN"]
        return @@access_token unless @@access_token.nil?
        raise ConfigurationError.new("Missing pCloud API access token")
      end

      def timeout_seconds_from_config_or_env
        @@timeout_seconds ||= ENV.fetch("PCLOUD_API_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS).to_i
        return @@timeout_seconds unless @@timeout_seconds.zero?
        raise ConfigurationError.new("Invalid pCloud API timeout seconds: cannot be set to 0")
      end

      # You can manually hit "https://<default_server_for_your_region>/getapiserver"
      # to get some JSON which will tell you if there is a server in your region
      # closer to you than the default.
      def closest_server
        @@closest_server ||= begin
          return ENV["PCLOUD_API_BASE_URI"] if ENV["PCLOUD_API_BASE_URI"]
          case data_region_from_config_or_env
          when US_DATA_REGION
            US_API_BASE
          when EU_DATA_REGION
            EU_API_BASE
          else
            raise ConfigurationError.new("Invalid pCloud data region, must be one of #{VALID_DATA_REGIONS}")
          end
        end
      end
    end
  end
end
