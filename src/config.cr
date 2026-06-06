module Dirless
  module CLI
    module Config
      DEFAULT_DIR = "/etc/dirless"

      @@dir : String = DEFAULT_DIR

      def self.dir : String
        @@dir
      end

      def self.age_key_path : String
        File.join(@@dir, "age.key")
      end

      def self.hmac_key_path : String
        File.join(@@dir, "hmac.key")
      end

      def self.agent_config_path : String
        File.join(@@dir, "dirless-agent.toml")
      end

      def self.enrollment_files : Array(String)
        [age_key_path]
      end

      KEY_FILE_PERMS = 0o600
      DIR_PERMS      = 0o700

      def self.with_dir(path : String, &)
        previous = @@dir.dup
        @@dir = path
        yield
      ensure
        @@dir = previous || DEFAULT_DIR
      end
    end
  end
end
