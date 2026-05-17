require "option_parser"
require "http/client"
require "uri"
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

      private struct EnrollOptions
        getter token : String
        getter server : String
        getter tenant_id : String?
        getter ca_cert_path : String?
        getter ca_key_path : String?
        getter? overwrite : Bool
        getter? regenerate_hmac : Bool

        def initialize(
          @token : String,
          @server : String,
          @tenant_id : String?,
          @ca_cert_path : String?,
          @ca_key_path : String?,
          @overwrite : Bool,
          @regenerate_hmac : Bool,
        )
        end
      end

      class Enroll
        CERT_VALIDITY_DAYS = 3650 # 10 years

        def self.run(args : Array(String)) : Nil
          new.run(args)
        rescue ex : EnrollError
          STDERR.puts ex.message
          exit 1
        end

        def run(args : Array(String)) : Nil
          opts = parse_options(args)
          execute(opts)
        end

        private def parse_options(args : Array(String)) : EnrollOptions
          token : String? = nil
          server : String? = nil
          tenant_id : String? = nil
          ca_cert_path : String? = nil
          ca_key_path : String? = nil
          overwrite = false
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

          if ca_cert_path.nil? != ca_key_path.nil?
            raise EnrollError.new("Error: --ca-cert and --ca-key must be provided together.")
          end

          if regenerate_hmac && !overwrite
            raise EnrollError.new("Error: --regenerate-hmac requires --overwrite-existing.")
          end

          resolved_token = require_opt(token, "--token")
          resolved_server = require_opt(server, "--server")

          EnrollOptions.new(
            token: resolved_token,
            server: resolved_server,
            tenant_id: tenant_id,
            ca_cert_path: ca_cert_path,
            ca_key_path: ca_key_path,
            overwrite: overwrite,
            regenerate_hmac: regenerate_hmac,
          )
        end

        private def execute(opts : EnrollOptions) : Nil
          # ── existing file check ──────────────────────────────────────────
          existing = Config.enrollment_files.select { |path| File.exists?(path) }
          if !existing.empty? && !opts.overwrite?
            msg = String.build do |io|
              io << "Error: enrollment files already exist:\n"
              existing.each { |path| io << "  #{path}\n" }
              io << "\nPass --overwrite-existing to overwrite them."
            end
            raise EnrollError.new(msg)
          end

          # ── tenant ID ────────────────────────────────────────────────────
          tenant_id = if tid = opts.tenant_id
                        puts "Using provided tenant ID: #{tid}"
                        tid
                      else
                        puts "Fetching AWS account ID from IMDS..."
                        # Use the enrollment token as HMAC key — same as dirless-syncer —
                        # so both nodes derive the same tenant ID and share the same backend DB.
                        write_file(Config.hmac_key_path, opts.token)
                        derived = Providers::AWS.tenant_id(opts.token)
                        puts "Derived tenant ID: #{derived}"
                        derived
                      end

          # ── age keypair ──────────────────────────────────────────────────
          puts "Generating age keypair..."
          age_keypair = Age.keygen

          # ── X.509 cert bundle ────────────────────────────────────────────
          bundle = if (cert_path = opts.ca_cert_path) && (key_path = opts.ca_key_path)
                     puts "Generating CA-signed certificate bundle..."
                     X509.generate(
                       common_name: tenant_id,
                       days: CERT_VALIDITY_DAYS,
                       ca_cert: File.read(cert_path),
                       ca_key: File.read(key_path),
                     )
                   else
                     puts "Generating self-signed certificate bundle..."
                     X509.generate(
                       common_name: tenant_id,
                       days: CERT_VALIDITY_DAYS,
                     )
                   end

          # ── write files ──────────────────────────────────────────────────
          puts "Writing enrollment files to #{Config.dir}..."
          FileUtils.mkdir_p(Config.dir)
          File.chmod(Config.dir, Config::DIR_PERMS)

          write_file(Config.ca_cert_path, bundle.ca_cert)
          write_file(Config.ca_key_path, bundle.ca_key)
          write_file(Config.client_cert_path, bundle.client_cert)
          write_file(Config.client_key_path, bundle.client_key)
          write_file(Config.age_key_path, age_keypair.secret_key.value)

          # ── POST /v1/enrollment/enroll ───────────────────────────────────
          puts "Enrolling with #{opts.server}..."
          enroll(
            server: opts.server,
            token: opts.token,
            tenant_id: tenant_id,
            age_public_key: age_keypair.public_key.value,
            ca_cert: bundle.ca_cert,
          )

          puts "\n✓ Enrollment complete."
          puts "  Tenant ID : #{tenant_id}"
          puts "  Files     : #{Config.dir}/"
        end

        private def require_opt(value : String?, flag : String) : String
          value || raise EnrollError.new("Error: #{flag} is required.")
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
          parsed_uri = URI.parse("#{server.rstrip("/")}/v1/enrollment/enroll")
          body = {
            tenant_id:      tenant_id,
            age_public_key: age_public_key,
            ca_cert:        ca_cert,
          }.to_json

          client = HTTP::Client.new(parsed_uri)
          client.connect_timeout = 10.seconds
          client.read_timeout = 30.seconds
          response = client.post(
            parsed_uri.request_target,
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
          when 401
            raise EnrollError.new("Error: invalid token — check --token matches the backend hmac_secret")
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
