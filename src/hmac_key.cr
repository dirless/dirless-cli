require "random/secure"
require "file"

module Dirless
  module CLI
    module HMACKey
      KEY_BYTES = 32 # 256-bit key

      # Loads the HMAC secret from *path* if it exists, otherwise generates
      # a fresh one, writes it to *path* with 0600 permissions, and returns it.
      def self.load_or_generate(path : String) : String
        if File.exists?(path)
          File.read(path).strip
        else
          generate_and_write(path)
        end
      end

      # Forces generation of a new HMAC secret, overwriting *path*.
      # Should only be called when --regenerate-hmac is explicitly passed.
      def self.regenerate(path : String) : String
        generate_and_write(path)
      end

      private def self.generate_and_write(path : String) : String
        secret = Random::Secure.hex(KEY_BYTES)
        File.write(path, secret)
        File.chmod(path, 0o600)
        secret
      end
    end
  end
end
