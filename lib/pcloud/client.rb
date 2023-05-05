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
