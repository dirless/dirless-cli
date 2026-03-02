module Dirless
  module CLI
    module Config
      DEFAULT_DIR = "/etc/dirless"

      @@dir : String = DEFAULT_DIR

      def self.dir : String
        @@dir
      end

      def self.ca_cert_path : String
        File.join(@@dir, "ca.crt")
      end

      def self.ca_key_path : String
        File.join(@@dir, "ca.key")
      end

      def self.client_cert_path : String
        File.join(@@dir, "client.crt")
      end

      def self.client_key_path : String
        File.join(@@dir, "client.key")
      end

      def self.age_key_path : String
        File.join(@@dir, "age.key")
      end

      def self.hmac_key_path : String
        File.join(@@dir, "hmac.key")
      end

      def self.enrollment_files : Array(String)
        [ca_cert_path, ca_key_path, client_cert_path, client_key_path, age_key_path]
      end

      KEY_FILE_PERMS = 0o600
      DIR_PERMS      = 0o700

      def self.with_dir(path : String, &)
        previous = @@dir.dup
        @@dir = path
        yield
      ensure
        @@dir = previous.not_nil!
      end
    end
  end
end
