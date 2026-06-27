require "http/client"
require "json"
require "openssl/hmac"

module Dirless
  module CLI
    module Providers
      module AWS
        IMDS_BASE     = "http://169.254.169.254"
        IMDS_TOKEN    = "#{IMDS_BASE}/latest/api/token"
        IMDS_IDENTITY = "#{IMDS_BASE}/latest/dynamic/instance-identity/document"
        TOKEN_TTL     = "21600" # seconds (6 hours, standard value)
        # Fetches the AWS account ID from IMDSv2.
        # Raises if IMDS is unreachable or the response is malformed.
        def self.account_id : String
          token = fetch_imds_token
          fetch_account_id(token)
        end

        # Derives the tenant ID: hmac_hex(hmac_secret, account_id)
        def self.tenant_id(hmac_secret : String) : String
          id = account_id
          OpenSSL::HMAC.hexdigest(:sha256, hmac_secret, id)
        end

        private def self.new_imds_client : HTTP::Client
          client = HTTP::Client.new("169.254.169.254")
          client.connect_timeout = 2.seconds
          client.read_timeout = 5.seconds
          client
        end

        private def self.fetch_imds_token : String
          client = new_imds_client
          response = client.put(
            "/latest/api/token",
            headers: HTTP::Headers{"X-aws-ec2-metadata-token-ttl-seconds" => TOKEN_TTL}
          )
          unless response.status_code == 200
            raise "IMDSv2 token request failed (HTTP #{response.status_code}). " \
                  "Are you running on an EC2 instance?"
          end
          response.body.strip
        rescue ex : Socket::ConnectError | IO::TimeoutError
          raise "Cannot reach AWS IMDS (#{IMDS_BASE}). " \
                "Are you running on an EC2 instance? " \
                "Pass an explicit tenant with 'dirless-cli enroll --tenant-id <id>' to skip IMDS " \
                "(see 'dirless-cli enroll --help'). (#{ex.message})"
        end

        private def self.fetch_account_id(token : String) : String
          client = new_imds_client
          response = client.get(
            "/latest/dynamic/instance-identity/document",
            headers: HTTP::Headers{"X-aws-ec2-metadata-token" => token}
          )
          unless response.status_code == 200
            raise "IMDS identity document request failed (HTTP #{response.status_code})."
          end
          parsed = JSON.parse(response.body)
          account_id = parsed["accountId"]?.try(&.as_s)
          raise "accountId not found in IMDS identity document." unless account_id
          unless account_id.match(/\A\d{12}\z/)
            raise "accountId from IMDS has unexpected format (expected 12 digits, got: #{account_id.inspect})"
          end
          account_id
        end
      end
    end
  end
end
