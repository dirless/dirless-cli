require "option_parser"
require "http/client"
require "json"
require "file_utils"
require "age-crystal"
require "x509-crystal"
require "../config"
require "../hmac_key"
require "../providers/aws"

module Dirless
  module CLI
    module Commands
      class EnrollError < Exception; end

      class Enroll
        CERT_VALIDITY_DAYS = 3650 # 10 years

        def self.run(args : Array(String)) : Nil
          new.run(args)
        rescue ex : EnrollError
          STDERR.puts ex.message
          exit 1
        end

        def run(args : Array(String)) : Nil
          # ── option defaults ──────────────────────────────────────────────
          tenant_id       : String? = nil
          token           : String? = nil
          server          : String? = nil
          ca_cert_path    : String? = nil
          ca_key_path     : String? = nil
          overwrite       = false
          regenerate_hmac = false

          OptionParser.parse(args) do |parser|
            parser.banner = "Usage: dirless-cli enroll [options]"

            parser.on("--tenant-id ID",
              "Tenant ID (default: derived from AWS IMDS + HMAC)") { |v| tenant_id = v }
            parser.on("--token TOKEN",
              "Bearer token issued at account creation (required)") { |v| token = v }
            parser.on("--server URL",
              "Enrollment endpoint URL (required)") { |v| server = v }
            parser.on("--ca-cert PATH",
              "Path to existing CA cert PEM (CA-signed mode)") { |v| ca_cert_path = v }
            parser.on("--ca-key PATH",
              "Path to existing CA key PEM (CA-signed mode)") { |v| ca_key_path = v }
            parser.on("--overwrite-existing",
              "Overwrite existing enrollment files") { overwrite = true }
            parser.on("--regenerate-hmac",
              "Generate a new HMAC secret (WARNING: changes tenant identity — " \
              "requires --overwrite-existing)") { regenerate_hmac = true }
            parser.on("-h", "--help", "Show this help") do
              puts parser
              exit 0
            end
          end

          # ── validation ───────────────────────────────────────────────────
          raise EnrollError.new("Error: --token is required.") unless token
          raise EnrollError.new("Error: --server is required.") unless server

          if ca_cert_path.nil? != ca_key_path.nil?
            raise EnrollError.new("Error: --ca-cert and --ca-key must be provided together.")
          end

          if regenerate_hmac && !overwrite
            raise EnrollError.new("Error: --regenerate-hmac requires --overwrite-existing.")
          end

          # ── existing file check ──────────────────────────────────────────
          existing = Config.enrollment_files.select { |f| File.exists?(f) }
          if existing.any? && !overwrite
            msg = String.build do |s|
              s << "Error: enrollment files already exist:\n"
              existing.each { |f| s << "  #{f}\n" }
              s << "\nPass --overwrite-existing to overwrite them."
            end
            raise EnrollError.new(msg)
          end

          # ── HMAC secret ──────────────────────────────────────────────────
          hmac_secret = if regenerate_hmac
            warn_hmac_regeneration
            HMACKey.regenerate(Config.hmac_key_path)
          else
            HMACKey.load_or_generate(Config.hmac_key_path)
          end

          # ── tenant ID ────────────────────────────────────────────────────
          resolved_tenant_id = if tenant_id
            puts "Using provided tenant ID: #{tenant_id}"
            tenant_id
          else
            puts "Fetching AWS account ID from IMDS..."
            id = Providers::AWS.tenant_id(hmac_secret)
            puts "Derived tenant ID: #{id}"
            id
          end

          # ── age keypair ──────────────────────────────────────────────────
          puts "Generating age keypair..."
          age_keypair = Age.keygen

          # ── X.509 cert bundle ────────────────────────────────────────────
          resolved_tenant_id = resolved_tenant_id.not_nil!
          bundle = if ca_cert_path && ca_key_path
            puts "Generating CA-signed certificate bundle..."
            X509.generate(
              common_name: resolved_tenant_id,
              days:        CERT_VALIDITY_DAYS,
              ca_cert:     File.read(ca_cert_path.not_nil!),
              ca_key:      File.read(ca_key_path.not_nil!),
            )
          else
            puts "Generating self-signed certificate bundle..."
            X509.generate(
              common_name: resolved_tenant_id,
              days:        CERT_VALIDITY_DAYS,
            )
          end

          # ── write files ──────────────────────────────────────────────────
          puts "Writing enrollment files to #{Config.dir}..."
          FileUtils.mkdir_p(Config.dir)
          File.chmod(Config.dir, Config::DIR_PERMS)

          write_file(Config.ca_cert_path,     bundle.ca_cert)
          write_file(Config.ca_key_path,      bundle.ca_key)
          write_file(Config.client_cert_path, bundle.client_cert)
          write_file(Config.client_key_path,  bundle.client_key)
          write_file(Config.age_key_path,     age_keypair.secret_key.value)

          # ── POST /v1/enrollment/enroll ───────────────────────────────────
          puts "Enrolling with #{server}..."
          enroll(
            server:         server.not_nil!,
            token:          token.not_nil!,
            tenant_id:      resolved_tenant_id,
            age_public_key: age_keypair.public_key.value,
            ca_cert:        bundle.ca_cert,
          )

          puts "\n✓ Enrollment complete."
          puts "  Tenant ID : #{resolved_tenant_id}"
          puts "  Files     : #{Config.dir}/"
        end

        private def write_file(path : String, content : String) : Nil
          File.write(path, content)
          File.chmod(path, Config::KEY_FILE_PERMS)
          puts "  wrote #{path}"
        end

        private def enroll(
          server : String,
          token : String,
          tenant_id : String,
          age_public_key : String,
          ca_cert : String,
        ) : Nil
          uri = "#{server.rstrip("/")}/v1/enrollment/enroll"
          body = {
            tenant_id:      tenant_id,
            age_public_key: age_public_key,
            ca_cert:        ca_cert,
          }.to_json

          response = HTTP::Client.post(
            uri,
            headers: HTTP::Headers{
              "Content-Type"  => "application/json",
              "Authorization" => "Bearer #{token}",
            },
            body: body,
          )

          case response.status_code
          when 200
            parsed = JSON.parse(response.body)
            puts "  Backend response: #{parsed["status"]?}"
          when 403
            parsed = JSON.parse(response.body)
            raise EnrollError.new("Error: enrollment rejected — #{parsed["error"]?}")
          when 422
            parsed = JSON.parse(response.body)
            raise EnrollError.new("Error: invalid request — #{parsed["error"]?}")
          else
            raise EnrollError.new(
              "Error: unexpected response from server (HTTP #{response.status_code}): #{response.body}"
            )
          end
        rescue ex : Socket::ConnectError | IO::TimeoutError
          raise EnrollError.new("Error: could not connect to #{server}. (#{ex.message})")
        end

        private def warn_hmac_regeneration : Nil
          STDERR.puts ""
          STDERR.puts "┌─────────────────────────────────────────────────────────┐"
          STDERR.puts "│                  ⚠  WARNING  ⚠                          │"
          STDERR.puts "│                                                          │"
          STDERR.puts "│  --regenerate-hmac will create a NEW tenant identity.   │"
          STDERR.puts "│  Your existing backend data will be ORPHANED and will   │"
          STDERR.puts "│  no longer be accessible under the current tenant.      │"
          STDERR.puts "│                                                          │"
          STDERR.puts "│  Only proceed if you intend to start fresh.             │"
          STDERR.puts "└─────────────────────────────────────────────────────────┘"
          STDERR.puts ""
          STDERR.print "Type 'yes' to confirm: "
          response = STDIN.gets.try(&.strip)
          raise EnrollError.new("Aborted.") unless response == "yes"
        end
      end
    end
  end
end
