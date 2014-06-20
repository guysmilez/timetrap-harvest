require 'net/http'
require 'json'
require 'uri'

begin
  Module.const_get('Timetrap')
rescue NameError
  module Timetrap;
    module Formatters; end
    module Config
      def self.[](key)
        {}
      end
    end
  end
end

class HarvestClient
  HARVEST_ADD_URI = URI('https://dscout.harvestapp.com/daily/add')

  attr_reader :email, :password

  def initialize(email, password)
    @email    = email
    @password = password
  end

  def post(payload)
    req = Net::HTTP::Post.new(HARVEST_ADD_URI.request_uri)
    req.basic_auth(email, password)
    req.body            = payload.to_json
    req['Content-Type'] = 'application/json'
    req['Accept']       = 'application/json'

    res = Net::HTTP.start(HARVEST_ADD_URI.hostname, HARVEST_ADD_URI.port, use_ssl: true) do |http|
      http.request(req)
    end
  end
end

class Timetrap::Formatters::Harvest
  HARVESTABLE_REGEX        = /@(.*)/
  DEFAULT_ROUND_IN_MINUTES = 15

  attr_reader :entries
  attr_writer :client, :timetrap_config

  def initialize(entries)
    @entries = entries
  end

  def client
    @client ||= HarvestClient.new(harvest_email, harvest_password)
  end

  def harvest_email
    Timetrap::Config['harvest']['email']
  end

  def harvest_password
    Timetrap::Config['harvest']['password']
  end

  def output
    entries_to_output = []

    harvest_entries do |harvestable|
      if info = info_for_code(harvestable.code)
        payload = format(harvestable.entry, info.project_id, info.task_id)

        client.post(payload)

        entries_to_output << harvestable.entry
      end
    end

    generate_ouput(entries_to_output)
  end

  def generate_ouput(entries)
    entries.map { |entry| "Submitted: #{entry[:note]}" }.join("\n")
  end

  def harvest_entries
    entries.each do |entry|
      if entry[:start] && entry[:end]
        if match = HARVESTABLE_REGEX.match(entry[:note])
          code = match[1]

          yield OpenStruct.new(entry: entry, code: code)
        end
      end
    end
  end

  def format(entry, project_id, task_id)
    { notes:      entry[:note],
      hours:      hours_for_time(entry[:start], entry[:end]),
      project_id: project_id,
      task_id:    task_id,
      spent_at:   entry[:start].strftime('%Y%m%d')
    }
  end

  def hours_for_time(start_time, end_time)
    minutes = (end_time - start_time) / 60
    rounded = round(minutes)
    hours   = (rounded / 60)
  end

  def round(minutes, nearest = round_in_minutes)
    (minutes % nearest).zero? ? minutes : (minutes + nearest) - (minutes % nearest)
  end

  private

  def info_for_code(code)
    if alias_config = harvest_aliases[code]
      alias_config = alias_config.split(' ')

      OpenStruct.new(project_id: alias_config[0], task_id: alias_config[1])
    end
  end

  def round_in_minutes
    @round_in_seconds ||= timetrap_config['harvest']['round_in_minutes'] || DEFAULT_ROUND_IN_MINUTES
  end

  def harvest_aliases
    @harvest_aliases ||= timetrap_config['harvest']['aliases']
  end

  def timetrap_config
    @timetrap_config ||= Timetrap::Config
  end
end