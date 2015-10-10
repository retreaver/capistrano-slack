require 'capistrano'
require 'capistrano/log_with_awesome'
require 'json'
require 'net/http'
require 'active_support/all'

module Capistrano
  module Slack

    def payload(announcement)
      {
          'channel' => fetch(:slack_room),
          'username' => fetch(:slack_username, ''),
          'text' => announcement,
          'icon_emoji' => fetch(:slack_emoji, ''),
          'parse' => fetch(:slack_parse, '')
      }.to_json
    end

    def slack_webhook_url
      fetch(:slack_webhook_url)
    end

    def slack_connect(message)
      begin
        uri = URI.parse(slack_webhook_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        request = Net::HTTP::Post.new(uri.request_uri)
        request.set_form_data(:payload => payload(message))
        http.request(request)
      rescue SocketError => e
        puts "#{e.message} or slack may be down"
      end
    end

    def slack_defaults
      if fetch(:slack_deploy_defaults, true) == true
        before 'deploy', 'slack:starting'
        before 'deploy:migrations', 'slack:starting'
        after 'deploy', 'slack:finished'
        after 'deploy:migrations', 'slack:finished'
      end
    end

    def self.extended(configuration)
      configuration.load do

        before('deploy') do
          slack_defaults
        end

        set :deployer do
          ENV['GIT_AUTHOR_NAME'] || `git config user.name`.chomp
        end

        namespace :slack do
          task :starting do
            announced_deployer = ActiveSupport::Multibyte::Chars.new(fetch(:deployer)).mb_chars.normalize(:kd).gsub(/[^\x00-\x7F]/, '').to_s
            message = fetch(:slack_starting_message, nil)
            unless message.present?
              reference = `git rev-parse HEAD`.to_s.strip.rstrip
              reference_url = reference.present? ? "<https://github.com/callpixels/callpixels/commit/#{reference}|#{reference[0..8]}>" : ''
              branch = fetch(:branch, nil)
              branch_url = ''
              if branch.present?
                if branch == 'master'
                  branch_url = '<https://github.com/callpixels/callpixels/tree/master|master>'
                else
                  branch_url = "<https://github.com/callpixels/callpixels/compare/master...#{branch}|#{branch}>"
                end
              end
              message = "#{announced_deployer} is deploying #{fetch(:application)} #{branch_url} to *#{fetch(:stage, 'production')}* (#{reference_url})"
            end
            slack_connect(message)
            set(:start_time, Time.now)
          end

          task :finished do
            begin
              announced_deployer = fetch(:deployer)
              message = fetch(:slack_finished_message, nil)
              unless message.present?
                message = "#{announced_deployer} deployed #{fetch(:application)} successfully"
                if start_time = fetch(:start_time, nil)
                  elapsed = Time.now.to_i - start_time.to_i
                  message << " in #{elapsed} seconds."
                else
                  message << "."
                end
              end
              slack_connect(message)
            end
          end
        end

      end
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::Slack)
end
