require 'mamiya/cli'

require 'net/http'
require 'net/https'
require 'uri'
require 'json'
require 'thor'

module Mamiya
  class CLI < Thor
    class Client < Thor
      class_option :master, aliases: '-u', type: :string
      class_option :application, aliases: %w(-a --app), type: :string

      desc "list-applications", "list applications"
      def list_applications
        puts master_get('/packages')["applications"]
      end

      desc "list-packages", "list-packages"
      def list_packages
        puts master_get("/packages/#{application}")["packages"]
      end

      desc "show-package", "show package meta data"
      method_option :format, aliases: %w(-f), type: :string, default: 'pp'
      def show_package(package)
        meta =  master_get("/packages/#{application}/#{package}")

        case options[:format]
        when 'pp'
          require 'pp'
          pp meta
        when 'json'
          require 'json'
          puts meta.to_json
        when 'yaml'
          require 'yaml'
          puts meta.to_yaml
        end
      end

      desc "list-agents", 'list agents'
      def list_agents
        payload = master_get("/agents")

        agents = payload["agents"].keys

        agents.each do |agent|
          puts "#{agent}\talive"
        end
        payload["failed_agents"].each do |agent|
          puts "#{agent}\tfailed"
        end
      end

      desc "show-agent AGENT", 'Show agent'
      method_option :format, aliases: %w(-f), type: :string, default: 'pp'
      def show_agent(agent)
        agent = master_get("/agents/#{agent}")

        case options[:format]
        when 'pp'
          require 'pp'
          pp agent
        when 'json'
          require 'json'
          puts agent.to_json
        when 'yaml'
          require 'yaml'
          puts agent.to_yaml
        end
      end

      desc "show-distribution package", "Show package distribution status"
      method_option :format, aliases: %w(-f), type: :string, default: 'text'
      method_option :verbose, aliases: %w(-v), type: :boolean
      def show_distribution(package)
        dist = master_get("/packages/#{application}/#{package}/distribution")

        case options[:format]
        when 'json'
          require 'json'
          puts dist.to_json
          return

        when 'yaml'
          require 'yaml'
          puts dist.to_yaml
          return
        end

        total = dist['distributed_count'] + dist['not_distributed_count']
        puts <<-EOF
Distribution status of #{application}/#{package}

ratio (distributed:total-agents):    #{"%.1f" % ((dist['distributed_count']/total.to_f)*100)}%
number of agents have package:       #{dist['distributed_count']}
number of agents don't have package: #{dist['not_distributed_count']}
        EOF

        if options[:verbose]
          puts ""
          dist['not_distributed'].each do |name|
            puts "#{name}\tnot_distributed"
          end
          dist['distributed'].each do |name|
            puts "#{name}\tdistributed"
          end
        end
      end

      desc "distribute package", "order distributing package to agents"
      def distribute(package)
        p master_post("/packages/#{application}/#{package}/distribute")
      end

      desc "refresh", "order refreshing agent status"
      def refresh
        p master_post('/agents/refresh')
      end

      desc "deploy PACKAGE", "Run distribute->prepare->finalize"
      def deploy
      end

      desc "rollback", "Switch back to previous release then finalize"
      def rollback
      end

      private

      def fatal!(msg)
        $stderr.puts msg
        exit 1
      end

      def application
        options[:application] or fatal!('specify application')
      end

      def master_get(path)
        master_http.start do |http|
          JSON.parse http.get(path).tap(&:value).body
        end
      end

      def master_post(path, data='')
        master_http.start do |http|
          response = http.post(path, data).tap(&:value)
          response.code == '204' ? true : JSON.parse(response.tap(&:value).body)
        end
      end

      def master_http
        url = master_url
        Net::HTTP.new(url.host, url.port).tap do |http|
          http.use_ssl = true if url.scheme == 'https'
        end
      end

      def master_url
        url = ENV["MAMIYA_MASTER_URL"] || options[:master]
        fatal! 'specify master URL via --master(-u) option or $MAMIYA_MASTER_URL' unless url
        URI.parse(url)
      end
    end

   desc "client", "client for master"
   subcommand "client", Client
  end
end