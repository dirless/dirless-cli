require "option_parser"
require "./commands/enroll"

module Dirless
  module CLI
    # Single source of truth: read the version straight from shard.yml at
    # compile time so the binary and the shard can never drift apart.
    VERSION = {{ read_file("#{__DIR__}/../shard.yml").lines.find(&.starts_with?("version:")).split(":")[1].strip }}

    def self.run(args : Array(String)) : Nil
      if args.empty?
        puts usage
        exit 0
      end

      subcommand = args.shift

      case subcommand
      when "enroll"
        Commands::Enroll.run(args)
      when "version", "--version", "-v"
        puts VERSION
      when "help", "--help", "-h"
        puts usage
      else
        STDERR.puts "Unknown command: #{subcommand}"
        STDERR.puts usage
        exit 1
      end
    end

    private def self.usage : String
      <<-USAGE
      dirless-cli #{VERSION}

      Usage:
        dirless-cli <command> [options]

      Commands:
        enroll    Enroll this node with the Dirless backend
        version   Print version

      Run 'dirless-cli <command> --help' for command-specific options.
      USAGE
    end
  end
end

Dirless::CLI.run(ARGV)
