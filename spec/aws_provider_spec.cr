require "./spec_helper"

# Realistic fixture matching the actual AWS instance identity document schema
IMDS_TOKEN_RESPONSE = "fake-imds-token-abc123"

IMDS_IDENTITY_FIXTURE = {
  "accountId"               => "123456789012",
  "instanceId"              => "i-1234567890abcdef0",
  "instanceType"            => "t3.micro",
  "region"                  => "us-east-1",
  "availabilityZone"        => "us-east-1a",
  "architecture"            => "x86_64",
  "imageId"                 => "ami-0abcdef1234567890",
  "privateIp"               => "10.0.1.42",
  "pendingTime"             => "2024-01-15T10:30:00Z",
  "devpayProductCodes"      => nil,
  "marketplaceProductCodes" => nil,
  "billingProducts"         => nil,
  "ramdiskId"               => nil,
  "kernelId"                => nil,
  "version"                 => "2017-09-30",
}.to_json

def stub_imds_happy_path
  WebMock.stub(:put, "169.254.169.254/latest/api/token")
    .with(headers: {"X-aws-ec2-metadata-token-ttl-seconds" => "21600"})
    .to_return(status: 200, body: IMDS_TOKEN_RESPONSE)

  WebMock.stub(:get, "169.254.169.254/latest/dynamic/instance-identity/document")
    .with(headers: {"X-aws-ec2-metadata-token" => IMDS_TOKEN_RESPONSE})
    .to_return(status: 200, body: IMDS_IDENTITY_FIXTURE)
end

describe Dirless::CLI::Providers::AWS do
  describe ".account_id" do
    it "returns the account ID from the IMDS identity document" do
      stub_imds_happy_path
      Dirless::CLI::Providers::AWS.account_id.should eq("123456789012")
    end

    it "raises a descriptive error when the token request returns non-200" do
      WebMock.stub(:put, "169.254.169.254/latest/api/token")
        .to_return(status: 401, body: "Unauthorized")

      expect_raises(Exception, /IMDSv2 token request failed/) do
        Dirless::CLI::Providers::AWS.account_id
      end
    end

    it "raises a descriptive error when the identity document request returns non-200" do
      WebMock.stub(:put, "169.254.169.254/latest/api/token")
        .to_return(status: 200, body: IMDS_TOKEN_RESPONSE)

      WebMock.stub(:get, "169.254.169.254/latest/dynamic/instance-identity/document")
        .to_return(status: 404, body: "Not Found")

      expect_raises(Exception, /identity document request failed/) do
        Dirless::CLI::Providers::AWS.account_id
      end
    end

    it "raises a descriptive error when accountId is missing from the response" do
      WebMock.stub(:put, "169.254.169.254/latest/api/token")
        .to_return(status: 200, body: IMDS_TOKEN_RESPONSE)

      WebMock.stub(:get, "169.254.169.254/latest/dynamic/instance-identity/document")
        .to_return(status: 200, body: {"instanceId" => "i-abc"}.to_json)

      expect_raises(Exception, /accountId not found/) do
        Dirless::CLI::Providers::AWS.account_id
      end
    end

    it "raises when IMDS is unreachable (no stub registered)" do
      # WebMock raises NetConnectNotAllowedError for unstubbed requests,
      # simulating a connection failure
      expect_raises(Exception) do
        Dirless::CLI::Providers::AWS.account_id
      end
    end

    it "raises when accountId is not exactly 12 digits (L4)" do
      WebMock.stub(:put, "169.254.169.254/latest/api/token")
        .to_return(status: 200, body: IMDS_TOKEN_RESPONSE)

      # 11 digits - invalid AWS account ID format
      WebMock.stub(:get, "169.254.169.254/latest/dynamic/instance-identity/document")
        .to_return(status: 200, body: {"accountId" => "12345678901"}.to_json)

      expect_raises(Exception, /unexpected format/) do
        Dirless::CLI::Providers::AWS.account_id
      end
    end

    it "raises when accountId contains non-digit characters (L4)" do
      WebMock.stub(:put, "169.254.169.254/latest/api/token")
        .to_return(status: 200, body: IMDS_TOKEN_RESPONSE)

      WebMock.stub(:get, "169.254.169.254/latest/dynamic/instance-identity/document")
        .to_return(status: 200, body: {"accountId" => "1234567890ab"}.to_json)

      expect_raises(Exception, /unexpected format/) do
        Dirless::CLI::Providers::AWS.account_id
      end
    end
  end

  describe ".tenant_id" do
    it "returns a 64-char hex string (SHA-256 HMAC)" do
      stub_imds_happy_path
      id = Dirless::CLI::Providers::AWS.tenant_id("test-secret")
      id.size.should eq(64)
      id.should match(/\A[0-9a-f]+\z/)
    end

    it "produces a 64-char hex HMAC (SHA-256)" do
      stub_imds_happy_path
      id = Dirless::CLI::Providers::AWS.tenant_id("test-secret")
      id.size.should eq(64)
      id.should match(/\A[0-9a-f]+\z/)
    end

    it "is deterministic for the same secret and account ID" do
      stub_imds_happy_path
      id1 = Dirless::CLI::Providers::AWS.tenant_id("stable-secret")

      stub_imds_happy_path
      id2 = Dirless::CLI::Providers::AWS.tenant_id("stable-secret")

      id1.should eq(id2)
    end

    it "produces different tenant IDs for different HMAC secrets" do
      stub_imds_happy_path
      id1 = Dirless::CLI::Providers::AWS.tenant_id("secret-a")

      stub_imds_happy_path
      id2 = Dirless::CLI::Providers::AWS.tenant_id("secret-b")

      id1.should_not eq(id2)
    end
  end
end
