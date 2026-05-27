require "./spec_helper"
require "../src/commands/enroll"

# Stub IMDS so enroll specs don't need a real EC2 environment
ENROLL_ACCOUNT_ID    = "999888777666"
ENROLL_IMDS_TOKEN    = "enroll-spec-token"
ENROLL_IMDS_IDENTITY = {"accountId" => ENROLL_ACCOUNT_ID, "region" => "us-east-1"}.to_json

ENROLL_SERVER = "https://enroll.example.com"

def stub_imds
  WebMock.stub(:put, "169.254.169.254/latest/api/token")
    .to_return(status: 200, body: ENROLL_IMDS_TOKEN)
  WebMock.stub(:get, "169.254.169.254/latest/dynamic/instance-identity/document")
    .to_return(status: 200, body: ENROLL_IMDS_IDENTITY)
end

def stub_backend(status : Int32, body : String)
  WebMock.stub(:post, "#{ENROLL_SERVER}/v1/enrollment/enroll")
    .to_return(status: status, body: body)
end

# Runs the enroll command with a temporary directory substituted for /etc/dirless.
# Yields the temp dir path so specs can assert on written files.
def with_enroll_tmpdir(extra_args : Array(String) = [] of String, &)
  tmpdir = File.tempname("dirless-enroll-spec")
  Dir.mkdir_p(tmpdir)

  # Patch the constants to point at tmpdir for this invocation
  # We do this by passing the dir via env-style helper below
  begin
    yield tmpdir
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end

# Helper that builds a minimal valid args list pointing at a given dir
def enroll_args(dir : String, extra : Array(String) = [] of String) : Array(String)
  ["--token", "test-bearer-token", "--server", ENROLL_SERVER] + extra
end

describe Dirless::CLI::Commands::Enroll do
  # ── option validation ──────────────────────────────────────────────────────

  describe "option validation" do
    it "exits when --token is missing" do
      expect_raises(Dirless::CLI::Commands::EnrollError) do
        Dirless::CLI::Commands::Enroll.new.run(["--server", ENROLL_SERVER])
      end
    end

    it "exits when --server is missing" do
      expect_raises(Dirless::CLI::Commands::EnrollError) do
        Dirless::CLI::Commands::Enroll.new.run(["--token", "tok"])
      end
    end

    it "exits when --regenerate-hmac is passed without --overwrite-existing" do
      expect_raises(Dirless::CLI::Commands::EnrollError) do
        Dirless::CLI::Commands::Enroll.new.run([
          "--token", "tok",
          "--server", ENROLL_SERVER,
          "--regenerate-hmac",
        ])
      end
    end
  end

  # ── file writing ───────────────────────────────────────────────────────────

  describe "file writing" do
    it "writes all expected files to the output directory" do
      stub_imds
      stub_backend(200, {"status" => "enrolled"}.to_json)

      with_enroll_tmpdir do |dir|
        # Override the config dir for this test
        Dirless::CLI::Config.with_dir(dir) do
          Dirless::CLI::Commands::Enroll.new.run(
            enroll_args(dir, ["--tenant-id", "test-tenant-123"])
          )

          File.exists?(File.join(dir, "age.key")).should be_true
        end
      end
    end

    it "writes key files with 0600 permissions" do
      stub_imds
      stub_backend(200, {"status" => "enrolled"}.to_json)

      with_enroll_tmpdir do |dir|
        Dirless::CLI::Config.with_dir(dir) do
          Dirless::CLI::Commands::Enroll.new.run(
            enroll_args(dir, ["--tenant-id", "test-tenant-123"])
          )

          path = File.join(dir, "age.key")
          perms = File.info(path).permissions
          (perms.value & 0o777).should eq(0o600), "age.key should be 0600"
        end
      end
    end

    it "writes a valid age secret key to age.key" do
      stub_imds
      stub_backend(200, {"status" => "enrolled"}.to_json)

      with_enroll_tmpdir do |dir|
        Dirless::CLI::Config.with_dir(dir) do
          Dirless::CLI::Commands::Enroll.new.run(
            enroll_args(dir, ["--tenant-id", "test-tenant-123"])
          )
          content = File.read(File.join(dir, "age.key")).strip
          content.should start_with("AGE-SECRET-KEY-1")
        end
      end
    end

    it "aborts when files exist and --overwrite-existing is not passed" do
      stub_imds

      with_enroll_tmpdir do |dir|
        Dirless::CLI::Config.with_dir(dir) do
          # Pre-create one of the enrollment files
          File.write(File.join(dir, "age.key"), "existing")

          expect_raises(Dirless::CLI::Commands::EnrollError) do
            Dirless::CLI::Commands::Enroll.new.run(
              enroll_args(dir, ["--tenant-id", "test-tenant-123"])
            )
          end
        end
      end
    end

    it "overwrites existing files when --overwrite-existing is passed" do
      stub_imds
      stub_backend(200, {"status" => "enrolled"}.to_json)

      with_enroll_tmpdir do |dir|
        Dirless::CLI::Config.with_dir(dir) do
          File.write(File.join(dir, "age.key"), "old-content")

          Dirless::CLI::Commands::Enroll.new.run(
            enroll_args(dir, ["--tenant-id", "test-tenant-123", "--overwrite-existing"])
          )

          content = File.read(File.join(dir, "age.key")).strip
          content.should_not eq("old-content")
          content.should start_with("AGE-SECRET-KEY-1")
        end
      end
    end
  end

  # ── backend POST ───────────────────────────────────────────────────────────

  describe "backend POST" do
    it "sends Authorization header with the bearer token" do
      stub_imds
      WebMock.stub(:post, "#{ENROLL_SERVER}/v1/enrollment/enroll")
        .with(headers: {"Authorization" => "Bearer test-bearer-token"})
        .to_return(status: 200, body: {"status" => "enrolled"}.to_json)

      with_enroll_tmpdir do |dir|
        Dirless::CLI::Config.with_dir(dir) do
          # Should not raise — the stub only matches if the header is present
          Dirless::CLI::Commands::Enroll.new.run(
            enroll_args(dir, ["--tenant-id", "test-tenant-123"])
          )
        end
      end
    end

    it "aborts with a clear message on 403 from backend" do
      stub_imds
      stub_backend(403, {"error" => "tenant is not authorized to enroll"}.to_json)

      with_enroll_tmpdir do |dir|
        Dirless::CLI::Config.with_dir(dir) do
          expect_raises(Dirless::CLI::Commands::EnrollError) do
            Dirless::CLI::Commands::Enroll.new.run(
              enroll_args(dir, ["--tenant-id", "test-tenant-123"])
            )
          end
        end
      end
    end

    it "aborts with a clear message on 422 from backend" do
      stub_imds
      stub_backend(422, {"error" => "invalid tenant_id format"}.to_json)

      with_enroll_tmpdir do |dir|
        Dirless::CLI::Config.with_dir(dir) do
          expect_raises(Dirless::CLI::Commands::EnrollError) do
            Dirless::CLI::Commands::Enroll.new.run(
              enroll_args(dir, ["--tenant-id", "test-tenant-123"])
            )
          end
        end
      end
    end

    it "aborts on unexpected HTTP status codes" do
      stub_imds
      stub_backend(500, "Internal Server Error")

      with_enroll_tmpdir do |dir|
        Dirless::CLI::Config.with_dir(dir) do
          expect_raises(Dirless::CLI::Commands::EnrollError) do
            Dirless::CLI::Commands::Enroll.new.run(
              enroll_args(dir, ["--tenant-id", "test-tenant-123"])
            )
          end
        end
      end
    end
  end

  # ── tenant ID derivation ───────────────────────────────────────────────────

  describe "tenant ID" do
    it "uses the provided --tenant-id directly without hitting IMDS" do
      # No IMDS stub — if IMDS is hit, WebMock will raise
      stub_backend(200, {"status" => "enrolled"}.to_json)

      with_enroll_tmpdir do |dir|
        Dirless::CLI::Config.with_dir(dir) do
          Dirless::CLI::Commands::Enroll.new.run(
            enroll_args(dir, ["--tenant-id", "explicit-tenant-id"])
          )
        end
      end
    end

    it "derives tenant ID from IMDS when --tenant-id is not passed" do
      stub_imds
      stub_backend(200, {"status" => "enrolled"}.to_json)

      with_enroll_tmpdir do |dir|
        Dirless::CLI::Config.with_dir(dir) do
          # Should complete without error — IMDS stubs provide the account ID
          Dirless::CLI::Commands::Enroll.new.run(enroll_args(dir))
        end
      end
    end
  end
end
