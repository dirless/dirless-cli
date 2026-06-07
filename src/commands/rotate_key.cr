require "option_parser"
require "http/client"
require "uri"
require "json"
require "toml"
require "age-crystal"
require "../config"

module Dirless
  module CLI
    module Commands
      class RotateKeyError < Exception; end

      class RotateKey
        def self.run(args : Array(String)) : Nil
          new.run(args)
        rescue ex : RotateKeyError
          STDERR.puts ex.message
          exit 1
        end

        def run(args : Array(String)) : Nil
          config_path = Config.agent_config_path

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: dirless-cli rotate-key [options]"
            parser.on("--config PATH", "Agent config file (default: #{config_path})") { |v| config_path = v }
            parser.on("-h", "--help", "Show this help") { puts parser; exit 0 }
          end

          unless File.exists?(config_path)
            raise RotateKeyError.new(
              "Error: agent config not found at #{config_path}\n" \
              "Is this node enrolled? Run 'dirless-cli enroll' first."
            )
          end

          toml = TOML.parse(File.read(config_path))
          backend_url = toml["backend"]["url"].as_s
          hmac_secret = toml["auth"]["hmac_secret"].as_s
          tenant_id   = toml["auth"]["tenant_id"].as_s
          age_key_path = toml["local"]["age_key_path"].as_s

          unless File.exists?(age_key_path)
            raise RotateKeyError.new("Error: age key not found at #{age_key_path}")
          end

          secret_key_str = File.read(age_key_path).strip
          _, sec_bytes   = Age::Bech32.decode(secret_key_str)
          pub_bytes      = Age::X25519.public_from_private(sec_bytes)
          public_key     = Age::Bech32.encode("age", pub_bytes)

          puts "Host age public key : #{public_key}"
          puts "Updating backend at : #{backend_url}"

          uri    = URI.parse("#{backend_url.rstrip("/")}/v1/snapshot/public-key")
          client = HTTP::Client.new(uri)
          client.connect_timeout = 10.seconds
          client.read_timeout = 30.seconds

          response = client.put(
            uri.request_target,
            headers: HTTP::Headers{
              "Content-Type"  => "application/json",
              "Authorization" => "Bearer #{hmac_secret}",
              "X-Tenant-ID"   => tenant_id,
            },
            body: {"age_public_key" => public_key}.to_json,
          )

          case response.status_code
          when 200
            puts "\n✓ Backend key updated."
            puts "  The next syncer push will re-encrypt snapshots for this host."
            puts "  Re-save any portal-managed local users to re-encrypt them for the new key."
          when 401
            raise RotateKeyError.new("Error: unauthorized - check the token in #{config_path}")
          when 422
            parsed = JSON.parse(response.body)
            raise RotateKeyError.new("Error: invalid key - #{parsed["error"]?}")
          else
            raise RotateKeyError.new("Error: unexpected response (HTTP #{response.status_code}): #{response.body}")
          end
        rescue ex : RotateKeyError
          raise ex
        rescue ex : Socket::Error | IO::TimeoutError | OpenSSL::SSL::Error
          raise RotateKeyError.new("Error: could not connect to backend - #{ex.message}")
        end
      end
    end
  end
end
