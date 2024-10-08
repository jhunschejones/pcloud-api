RSpec.describe Pcloud::Client do
  before(:each) do
    Pcloud::Client.remove_class_variable(:@@data_region) if Pcloud::Client.class_variable_defined?(:@@data_region)
    Pcloud::Client.remove_class_variable(:@@access_token) if Pcloud::Client.class_variable_defined?(:@@access_token)
    Pcloud::Client.remove_class_variable(:@@timeout_seconds) if Pcloud::Client.class_variable_defined?(:@@timeout_seconds)
    Pcloud::Client.remove_class_variable(:@@closest_server) if Pcloud::Client.class_variable_defined?(:@@closest_server)
  end

  describe ".execute" do
    let(:httparty_response) { double(HTTParty::Response) }

    before do
      Pcloud::Client.configure(access_token: "test-token", data_region: "US")
      allow(httparty_response).to receive(:body).and_return({ fileid: 100100 }.to_json)
      allow(HTTParty).to receive(:public_send).and_return(httparty_response)
    end

    context "when method is 'uploadfile'" do
      it "makes a post request to the pCloud api" do
        expect(HTTParty)
          .to receive(:public_send)
          .with(
            :post,
            "https://api.pcloud.com/uploadfile",
            {
              headers: { "Authorization" => "Bearer test-token" },
              timeout: 8,
              body: { filename: "cats.jpg" }
            }
          ).and_return(httparty_response)
        Pcloud::Client.execute("uploadfile", body: { filename: "cats.jpg" })
      end

      it "returns the JSON response" do
        response = Pcloud::Client.execute("uploadfile", body: { filename: "cats.jpg" })
        expect(response).to eq({ "fileid" => 100100 })
      end
    end

    context "for all other methods" do
      it "makes a get request to the pCloud api" do
        expect(HTTParty)
          .to receive(:public_send)
          .with(
            :get,
            "https://api.pcloud.com/stat",
            {
              headers: { "Authorization" => "Bearer test-token" },
              timeout: 8,
              query: { fileid: 100100 }
            }
          ).and_return(httparty_response)
        Pcloud::Client.execute("stat", query: { fileid: 100100 })
      end

      it "returns the JSON response" do
        response = Pcloud::Client.execute("stat", query: { fileid: 100100 })
        expect(response).to eq({ "fileid" => 100100 })
      end
    end

    context "when pCloud returns an error in the JSON" do
      before do
        allow(httparty_response).to receive(:body).and_return({ error: "Don't do it David" }.to_json)
      end

      it "raises an ErrorResponse" do
        allow(HTTParty).to receive(:public_send).and_return(httparty_response)
        expect {
          Pcloud::Client.execute("stat", query: { fileid: 100100 })
        }.to raise_error(Pcloud::Client::ErrorResponse, "Don't do it David")
      end
    end
  end

  describe ".generate_access_token" do
    let(:httparty_response) { double(HTTParty::Response) }

    before do
      # silence console output from the interactive CLI
      allow(Pcloud::Client).to receive(:puts)
      allow(Pcloud::Client).to receive(:print)

      allow(httparty_response).to receive(:body).and_return({ access_token: "Here's your access token!" }.to_json)
      allow(HTTParty).to receive(:post).and_return(httparty_response)
    end

    it "makes the expected web request to get an access token" do
      client_id = "my_client_id"
      client_secret = "my_client_secret"
      access_code = "pcloud_access_code"

      allow($stdin).to receive(:gets).and_return(
        client_id,
        client_secret,
        "EU", # user specified data region
        access_code, # access code provided by pCloud
      )
      expect(HTTParty)
        .to receive(:post)
        .with(
          "https://eapi.pcloud.com/oauth2_token?client_id=#{client_id}&client_secret=#{client_secret}&code=#{access_code}",
          { headers: { "Accept" => "application/json" } }
        ).and_return(httparty_response)

      Pcloud::Client.generate_access_token
    end
  end

  describe ".data_region_from_config_or_env" do
    it "reads from module configuration" do
      Pcloud::Client.configure(access_token: "test-token", data_region: "EU")
      expect(Pcloud::Client.send(:data_region_from_config_or_env)).to eq("EU")
    end

    it "reads from environment variable" do
      allow(ENV).to receive(:[]).with("PCLOUD_API_DATA_REGION").and_return("EU")
      expect(Pcloud::Client.send(:data_region_from_config_or_env)).to eq("EU")
    end

    it "raises ConfigurationError when not configured" do
      expect {
        Pcloud::Client.send(:data_region_from_config_or_env)
      }.to raise_error(Pcloud::Client::ConfigurationError, "Missing pCloud data region")
    end

    it "raises ConfigurationError when set to an invalid value" do
      allow(ENV).to receive(:[]).with("PCLOUD_API_DATA_REGION").and_return("SPACE")
      expect {
        Pcloud::Client.send(:data_region_from_config_or_env)
      }.to raise_error(Pcloud::Client::ConfigurationError, 'Invalid pCloud data region, must be one of ["EU", "US"]')
    end
  end

  describe ".access_token_from_config_or_env" do
    it "reads from module configuration" do
      Pcloud::Client.configure(access_token: "test-token", data_region: "EU")
      expect(Pcloud::Client.send(:access_token_from_config_or_env)).to eq("test-token")
    end

    it "reads from environment variable" do
      allow(ENV).to receive(:[]).with("PCLOUD_API_ACCESS_TOKEN").and_return("test-token")
      expect(Pcloud::Client.send(:access_token_from_config_or_env)).to eq("test-token")
    end

    it "raises ConfigurationError when not configured" do
      expect {
        Pcloud::Client.send(:access_token_from_config_or_env)
      }.to raise_error(Pcloud::Client::ConfigurationError, "Missing pCloud API access token")
    end
  end

  describe ".timeout_seconds_from_config_or_env" do
    it "reads from module configuration" do
      Pcloud::Client.configure(access_token: "test-token", data_region: "EU", timeout_seconds: 60)
      expect(Pcloud::Client.send(:timeout_seconds_from_config_or_env)).to eq(60)
    end

    it "reads from environment variable" do
      allow(ENV).to receive(:fetch).with("PCLOUD_API_TIMEOUT_SECONDS", anything).and_return("60")
      expect(Pcloud::Client.send(:timeout_seconds_from_config_or_env)).to eq(60)
    end

    it "sets a default value when none is provided via env var or config setting" do
      expect(Pcloud::Client.send(:timeout_seconds_from_config_or_env)).to eq(Pcloud::Client::DEFAULT_TIMEOUT_SECONDS)
    end

    it "raises ConfigurationError when set to 0" do
      Pcloud::Client.configure(access_token: "test-token", data_region: "EU", timeout_seconds: 0)
      expect {
        Pcloud::Client.send(:timeout_seconds_from_config_or_env)
      }.to raise_error(Pcloud::Client::ConfigurationError, "Invalid pCloud API timeout seconds: cannot be set to 0")
    end
  end

  describe ".closest_server" do
    before do
      allow(ENV).to receive(:[]).and_call_original
    end

    it "returns the correct server for the US" do
      allow(ENV).to receive(:[]).with("PCLOUD_API_DATA_REGION").and_return("US")
      expect(Pcloud::Client.send(:closest_server)).to eq("api.pcloud.com")
    end

    it "returns the correct server for the EU" do
      allow(ENV).to receive(:[]).with("PCLOUD_API_DATA_REGION").and_return("EU")
      expect(Pcloud::Client.send(:closest_server)).to eq("eapi.pcloud.com")
    end

    it "allows manual override with PCLOUD_API_BASE_URI environment variable" do
      allow(ENV).to receive(:[]).with("PCLOUD_API_BASE_URI").and_return("spacecats.pcloud.com")
      expect(Pcloud::Client.send(:closest_server)).to eq("spacecats.pcloud.com")
    end

    it "raises ConfigurationError when retion is set to an invalid value" do
      allow(ENV).to receive(:[]).with("PCLOUD_API_DATA_REGION").and_return("SPACE")
      expect {
        Pcloud::Client.send(:closest_server)
      }.to raise_error(Pcloud::Client::ConfigurationError, 'Invalid pCloud data region, must be one of ["EU", "US"]')
    end
  end
end
