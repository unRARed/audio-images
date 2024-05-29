#!/usr/bin/env ruby -I ../lib -I lib
# frozen_string_literal: true

require "sinatra/base"
require "sinatra/reloader"
require "slim"
require "openai"
require "open-uri"
require "yaml"
require "fileutils"
require "securerandom"
require "byebug"
Dir.glob("./lib/**/*.rb").each{|f| require f }
Dir.glob("./custom_actions/**/*.rb").each{|f| require f }

class App < Sinatra::Base
  include Helpers
  include OpenAi
  include Actions
  include CustomActions

  configure :development do
    register Sinatra::Reloader
  end

  # Adds "feathered edge" to all images found in "project_root"
  #
  # TODO: Refactor as a custom action since it's wide in scope.
  # Also, make it only affect the :stash.
  #
  # def self.feather(cache)
  #   Dir.glob(App.working_images_pattern(cache)).each do |path|
  #     next if path.include? "--feathered"

  #     parts = path.split('.')
  #     output = "#{parts[0]}--feathered.#{parts[1]}"

  #     App.debug " -> Feathering #{output}"
  #     system(
  #       "convert #{path} ./bgw_edge.png -alpha off " \
  #       "-compose CopyOpacity " \
  #       "-composite #{output}"
  #     )

  #     File.delete(path) if File.exist? path
  #   end
  # end

  # Makes the image black and white in a "Chiaroscuro" style.
  #
  # TODO: Refactor as a custom action since it's a too specific.
  #

  ############
  ## Routes ##
  ############

  get '/' do
    App.debug "Loaded index"
    @data = {
      dalle_models: App.dalle_models
    }
    slim :index, locals: { data: @data }
    #App.style + App.form
  end

  # Takes an audio file and asks OpenAI to do the following:
  #
  #   - Determine Transcription
  #   - Generate a number of "prompts" from the Transcription
  #   - Summarize the "prompts" to establish overall context
  #   - Generate an image for each Prompt
  #
  post '/' do
    App.debug "Parsing Form Data"
    begin
      @cache = App.find_or_create_project(params)
      if params["audio"]
        @cache = App.transcribe(
          File.open(params["audio"]["tempfile"], "rb"),
          @cache
        )
      end
      unless @cache[:transcription]
        raise ArgumentError, 'No transcription'
      end
      @cache = App.generate_prompts(@cache)
      @cache = App.summarize(@cache)
      @cache = App.generate_images(@cache)

      redirect "/projects/#{@cache[:project_id]}"
    rescue StandardError => e
      if e.message.include? "OpenAI HTTP Error"
        App.debug e.message
        next
      end
      "<h3 style='color: #{App.colors["red"]};'>#{e.message}</h3>"
    end
  end

  App.actions.each do |action|
    post "/projects/:project_id/#{action.to_s}" do
      App.debug "Executing #{action} for #{params['project_id']}"
      cache = App.load_cache_for_project(params["project_id"])

      App.stash(cache)
      App.send(action, cache)
      cache[action] = true
      App.write_cache(cache)

      redirect "/projects/#{cache[:project_id]}"
    end
  end

  get "/projects/:project_id/?" do
    App.debug "Loading Project #{params["project_id"]}"
    @cache = App.load_cache_for_project(params["project_id"])

    if @cache
      @images = Dir.glob(
        App.project_root(params["project_id"]) + "/**/*.png"
      )
    end
    slim :project
  end

  get '/projects/:project_id/:image_file_name' do
    path = "/#{params["project_id"]}/#{params["image_file_name"]}"
    identifier = params["image_file_name"].split("--").first

    cache = App.load_cache_for_project(params["project_id"])
    if (
      cache && cache[:images] &&
      cache[:images].any?{|item| item[:path].
        include? identifier }
    )
      App.debug "Sending #{path}"
      send_file(
        App.project_root(params["project_id"]) +
          "/#{params["image_file_name"]}",
        :type => :png
      )
    else
      App.debug 'File path not found in cache'
      ""
    end
  end

  run!
end
