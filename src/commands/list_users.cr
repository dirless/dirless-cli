require "trash-panda-db"

module Dirless
  module CLI
    module Commands
      class ListUsers
        DB_PATH = "/var/lib/dirless/local.db"

        def self.run : Nil
          unless File.exists?(DB_PATH)
            STDERR.puts "Error: local snapshot not found at #{DB_PATH}"
            STDERR.puts "Is the dirless-agent installed and running?"
            exit 1
          end

          db = DB.open("trashpanda:#{DB_PATH}")
          db.exec("PRAGMA query_only = ON")
          db.exec("PRAGMA busy_timeout = 5000")

          rows = db.query_all(
            "SELECT username, uid, gid, home, shell FROM users ORDER BY uid",
            as: {String, Int64?, Int64?, String, String}
          )

          if rows.empty?
            puts "No users in local snapshot."
            return
          end

          puts "%-32s %6s %6s  %-24s  %s" % ["USERNAME", "UID", "GID", "HOME", "SHELL"]
          puts "-" * 80
          rows.each do |username, uid, gid, home, shell|
            puts "%-32s %6s %6s  %-24s  %s" % [username, uid, gid, home, shell]
          end
        ensure
          db.try(&.close)
        end
      end
    end
  end
end
