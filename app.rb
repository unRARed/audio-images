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

CustomActions.class_eval do
  DependentActionError = Class.new(StandardError)
end

class App < Sinatra::Base
  include Helpers
  include OpenAi
  include Actions
  include CustomActions

  configure :development do
    register Sinatra::Reloader
  end

  IP_ADDRESS =
    Socket.
      ip_address_list.
      map{|addr| addr.inspect_sockaddr }.
      reject do |addr|
        addr.length > 15 ||
          addr == "127.0.0.1" ||
          addr.count(".") < 3
      end.
      first

  set :bind, IP_ADDRESS
  set :port, ENV["PORT"] || 5001

  use Rack::Auth::Basic, 'Restricted Area' do |username, password|
    username == '' && password == ENV['BASIC_AUTH_PASSWORD']
  end

  # Prompts the user for the following information:
  #
  #   - Audio File to Transcribe
  #   - Number of Prompts/Images to Generate
  #   - Context (optional/recommended)
  #   - Style (optional)
  #   - Open AI Image Model to use
  #
  get '/' do
    App.debug "Loaded index"
    @data = {
      dalle_models: App.dalle_models
    }
    slim :index, locals: { data: @data }
  end

  # Generates all the things based on the form
  # data submitted in the prior step.
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

  # See ./lib/actions.rb for the list of actions. Custom
  # actions can be added to the CustomActions module.
  #
  App.actions.each do |action|
    post "/projects/:project_id/#{action.to_s}" do
      App.debug "Executing #{action} for #{params['project_id']}"
      cache = App.load_cache_for_project(params["project_id"])

      App.stash(cache)
      App.send(action, cache)
      cache[action] = true
      App.write_cache(cache)

      redirect "/projects/#{cache[:project_id]}"
    rescue DependentActionError => e
      @cache = cache
      @error = e.message
      slim :project
    end
  end

  # Displays the project page with all the generated content
  # and the available actions to be taken on the images.
  #
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

  # Serves the images generated for the project.
  #
  # NOTE: This is probably unsafe and should only be used
  #       for local experimentation. That goes for the entire
  #       app, really.
  #
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
