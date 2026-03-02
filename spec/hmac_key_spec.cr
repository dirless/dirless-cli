require "./spec_helper"

describe Dirless::CLI::HMACKey do
  describe ".load_or_generate" do
    it "generates a new key when file does not exist" do
      path = File.tempname("dirless-spec-hmac", ".key")
      File.delete(path) if File.exists?(path)

      key = Dirless::CLI::HMACKey.load_or_generate(path)
      key.should_not be_empty
      File.exists?(path).should be_true
    ensure
      File.delete(path) if path && File.exists?(path)
    end

    it "returns the same key on subsequent calls" do
      path = File.tempname("dirless-spec-hmac", ".key")
      File.delete(path) if File.exists?(path)

      key1 = Dirless::CLI::HMACKey.load_or_generate(path)
      key2 = Dirless::CLI::HMACKey.load_or_generate(path)
      key1.should eq(key2)
    ensure
      File.delete(path) if path && File.exists?(path)
    end

    it "writes the key with 0600 permissions" do
      path = File.tempname("dirless-spec-hmac", ".key")
      File.delete(path) if File.exists?(path)

      Dirless::CLI::HMACKey.load_or_generate(path)
      perms = File.info(path).permissions
      (perms.value & 0o777).should eq(0o600)
    ensure
      File.delete(path) if path && File.exists?(path)
    end
  end

  describe ".regenerate" do
    it "produces a different key than the previous one" do
      path = File.tempname("dirless-spec-hmac", ".key")

      key1 = Dirless::CLI::HMACKey.load_or_generate(path)
      key2 = Dirless::CLI::HMACKey.regenerate(path)
      key1.should_not eq(key2)
    ensure
      File.delete(path) if path && File.exists?(path)
    end
  end
end
