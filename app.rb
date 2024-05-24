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
Dir.glob("./custom_actions/**/*.rb").each{|f| require f }

class App < Sinatra::Base
  include CustomActions

  configure :development do
    register Sinatra::Reloader
  end

  # Allows hiding or showing the debug information by
  # settings the DEBUG environment variable at runtime.
  #
  #   Example: `DEBUG=1 ruby app.rb`
  #
  def self.debug(msg)
    return unless !ENV["DEBUG"].nil?

    count = msg.length
    divider = []
    [msg.length, 79].min.times{ divider << "-" }
    puts divider.join
    puts "DEBUG: #{msg}"
    puts divider.join
  end

  # The config for the Open AI Library. Assumes the
  # environment variable "OPENAI_API_KEY" is set.
  #
  def self.open_ai
    @open_ai ||= OpenAI::Client.new(
      access_token:ENV["OPENAI_API_KEY"],
      request_timeout: 480,
      log_errors: true
    )
  end

  # The prompt wrapper for the call to DALL-E. It should create
  # an image specific to the prompt given and consider the
  # :style in the cache object (if supplied).
  #
  # NOTE: Considering the :context and/or the :summary here seems
  #       to cause DALL-E to become liberal with the use of text
  #       in the images it generates.
  #
  def self.sketch_prompt(prompt, cache)
    parts = []
    parts <<  "I NEED to test how the tool works with extremely " \
      "simple prompts. DO NOT add any detail, just use it AS-IS:"
    if !cache[:style].nil?
      parts << "#{' In the style of "' + cache[:style] + '", '}" \
        "depict \"#{prompt}\"."
    else
      parts << "\"#{prompt}\"."
    end
    parts << "This image is for someone who CANNOT read."
    parts.join(' ')
  end

  # Loads, reads and parses /projects/:project_id/cache.yml
  # for keeping track of project-specific metadata.
  #
  def self.load_cache(project_id)
    YAML.load(
      File.open("#{App.project_root(project_id)}/cache.yml")
    )
  end

  # Loads existing cache for the :project_id if found,
  # otherwise creates new project folder and cache file.
  #
  def self.find_or_create_project(form_params)
    App.debug "Submitted: #{form_params.to_s}"

    if (
      form_params["project_id"] && File.exist?(
        "#{App.project_root(form_params["project_id"])}/cache.yml"
      )
    )
      App.debug 'existing project'
      cache = App.load_cache(form_params["project_id"])
    else
      App.debug 'new project'
      cache = {}
      cache[:project_id] = SecureRandom.urlsafe_base64.
        gsub(/[^a-zA-Z\d]/, '').slice(0..6).downcase
      if form_params["audio"]
        cache[:audio_file_name] = form_params["audio"]["filename"]
      end
      cache[:prompt_count] =
        (
          form_params["prompt_count"] &&
          form_params["prompt_count"] != ""
        ) ? form_params["prompt_count"].to_i : 1
      if form_params["context"] && form_params["context"] != ""
        cache[:context] = form_params["context"]
      end
      if form_params["style"] && form_params["style"] != ""
        cache[:style] = form_params["style"]
      end
      cache[:image_model] = form_params["image_model"]
      unless Dir.exist?(App.project_root(cache[:project_id]))
        Dir.mkdir(App.project_root(cache[:project_id]))
      end
      App.write(cache)
    end
    cache
  end

  # Replaces all images found in the project root with a
  # 3x upscaled version.
  #
  # TODO: Maybe refactor as a different grouping of actions
  #       since this affects ALL the images and should
  #       probably skip the stash step.
  #
  def self.upscale(cache)
    Dir.glob(App.working_images_pattern(cache)).each do |path|
      next if path.include? "--upscaled"

      parts = path.split('.')
      output = "#{parts[0]}-upscaled.#{parts[1]}"

      App.debug "Upscaling to #{output}"
      system(
        "./realesrgan-ncnn-vulkan " \
        "-s 3 -v " \
        "-i #{path} " \
        "-o #{parts[0]}--upscaled.#{parts[1]}"
      )

      File.delete(path) if File.exist? path
    end
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
  # def self.normalize(cache)
  #   Dir.glob("#{App.project_root(cache[:project_id])}/*.png").each do |path_to_image|
  #     next if path_to_image.include? "--normalized"

  #     parts = path_to_image.split('.')
  #     output = "#{parts[0]}--normalized.#{parts[1]}"

  #     App.debug " -> Normalizing #{output}"
  #     system(
  #       "convert #{path_to_image} " \
  #       "-brightness-contrast 15x60 -colorspace GRAY #{output}"
  #     )

  #     File.delete(path_to_image) if File.exist? path_to_image
  #   end
  # end

  # Compresses all images found in the project root.
  #
  # TODO: Maybe refactor as a different grouping of actions
  #       since this affects ALL the images and should
  #       probably skip the stash step.
  #
  def self.compress(cache)
    Dir.glob("#{App.project_root(cache[:project_id])}/**/*.png").each do |path_to_image|
      next if path_to_image.include? "--compressed"

      parts = path_to_image.split('.')
      output = "#{parts[0]}--compressed.#{parts[1]}"

      App.debug " -> Compressing #{output}"
      system(
        "pngquant -f --speed 1 --strip #{path_to_image} " \
        "--ext --compressed.png"
      )

      File.delete(path_to_image) if File.exist? path_to_image
    end
  end

  # Converts audio file to text and writes it to
  # the cache object, returning it
  def self.transcribe(file, cache)
    App.debug "self.transcribe"
    unless cache[:transcription]
      step1_response = App.open_ai.audio.translate(
        parameters: {
          model: "whisper-1",
          file: ,
        }
      )
      cache[:transcription] = step1_response["text"]

      App.debug "Transcription Complete"
      App.write(cache)
    end
    cache
  end

  # Converts transcribed text to a number of prompts and
  # writes them to the cache object, returning it
  def self.generate_prompts(cache)
    App.debug "Generating Prompts"
    unless cache[:transcription]
      raise ArgumentError, "No transcription"
    end

    unless cache[:prompts]
      step2_response = App.open_ai.chat(
        parameters: {
          model: "gpt-4o",
          # model: "gpt-3.5-turbo", # good enough?
          response_format: { type: "json_object" },
          messages: [{
            role: "user",
            content: "Please consider this full text following " \
              "the colon and concisely summarize " \
              "#{cache[:prompt_count].to_s} 'prompts' " \
              "optimized for #{cache[:image_model].to_s} " \
              "image generation. They " \
              "should be one or two sentences each." \
              "#{' Keep in mind ' + cache[:context] + "." if !cache[:context].nil?} " \
              " Produce a JSON array of strings under the " \
              "attribute name 'prompts'. The total character " \
              "count of the prompts should be less than " \
              "or equal to 1000:\n\n#{cache[:transcription]}."
          }],
          temperature: 0.7,
        }
      )

      content =
        step2_response["choices"].first["message"]["content"]

      cache[:prompts] = JSON.parse(content)["prompts"]

      App.debug "Prompt Extraction Complete"
      App.write(cache)
    end
    cache
  end

  # Converts prompts to a short summary and writes
  # is to the cache object, returning it
  def self.summarize(cache)
    App.debug "Summarizing Prompts"
    unless cache[:prompts]
      raise ArgumentError, "No prompts to summarize"
    end
    # Step 3: Summarize the prompts
    unless cache[:summary]
      step3_response = App.open_ai.chat(
        parameters: {
          model: "gpt-4o",
          # model: "gpt-3.5-turbo", # good enough?
          response_format: { type: "json_object" },
          messages: [{
            role: "user",
            content: "Please summarize this text in only 2 " \
              "sentences: #{cache[:prompts].join(' ')}. " \
              "#{'Keep in mind ' + cache[:context] + ". " if !cache[:context].nil?} " \
              "Please produce the response as JSON under the " \
              "attribute name 'summary'."
          }],
          temperature: 0.7,
        }
      )

      content =
        step3_response["choices"].first["message"]["content"]

      cache[:summary] = JSON.parse(content)["summary"]

      App.debug "Summary Generation Complete"
      App.write(cache)
    end
    cache
  end

  # Converts prompts to a images and writes
  # is to the cache object, returning it
  def self.generate_images(cache)
    App.debug "Generating Images"
    unless cache[:prompts]
      raise ArgumentError, "No prompts to base images on"
    end
    unless cache[:summary]
      raise ArgumentError, "No summary to use for context"
    end

    cache[:images] ||= []
    previously_generated = Dir.
      glob("#{App.project_root(cache[:project_id])}/*.png")

    # Only continue when we have more prompts than images
    unless previously_generated.length >= cache[:prompts].length
      cache[:prompts].each_with_index do |prompt, i|
        image_path = ("%03d" % (i+1)) +
          "_" + prompt.gsub(" ", "-").
          gsub(/[^a-zA-Z\-]/, '') + ".png"
        # Bail if we already generated this one
        next if !cache[:images].nil? && cache[:images]&.
          any?{|item| item[:path] == image_path }

        original_prompt = App.sketch_prompt(prompt, cache)
        App.debug "Generating image for: #{original_prompt}\n"

        dalle_settings = {
          model: cache[:image_model],
          size: "1024x1024",
          quality: "standard",
          prompt: original_prompt
        }

        image_response = App.open_ai.images.
          generate(parameters: dalle_settings)

        next unless data = image_response["data"]&.first

        cache_item = {
          path: image_path,
          prompt: !data["revised_prompt"].nil? ?
            data["revised_prompt"] : original_prompt
        }
        App.debug "Image Generated:"
        App.debug cache_item

        URI.open(data["url"]) do |image|
          File.open("#{App.project_root(
            cache[:project_id])}/#{image_path}", "wb"
          ) do |file|
            file.write(image.read)
          end
        end
        cache[:images] << cache_item

        App.write(cache)
      end
    end
    cache
  end

  #############
  ## Helpers ##
  #############

  def self.actions
    [ :upscale, :compress ] +
      self.methods.select{|name| name.to_s.start_with?("custom_") }
  end

  def self.available_actions(cache)
    available_actions = []
    App.actions.each do |action|
      available_actions << action unless !cache[action].nil? && cache[action] == true
    end
    available_actions
  end

  def self.project_ids
    Dir.glob('./projects/**').
      map{|path| path.split('/').last}
  end

  def self.complete?(cache)
    return false unless [
      :project_id, :audio_file_name, :context, :image_model,
      :transcription, :summary, :prompts, :images
    ].all?{ |attr| cache.keys.include? attr }

    # App.debug cache[:images]&.count
    # App.debug cache[:prompts]&.count
    !cache[:images].nil? && !cache[:prompts].nil? &&
      cache[:images]&.count >= cache[:prompts]&.count
  end

  # Possible Open AI image generation models the user
  # can choose from.
  def self.dalle_models
    [ "dall-e-2", "dall-e-3" ]
  end

  # Color map for generating image variants with imagemagick
  # via the :colorize action.
  #
  def self.colors
    {
      "brown" => "#573320",
      "red" => "#910E0E",
      "green" => "#406F37",
      "navy" => "#102255",
      "gray" => "#75797B",
    }
  end

  # Returns the full path to the root folder for
  # the :project_id value given
  #
  #   Example: /Users/some_user/audio-images/projects/2fgdaf"
  #
  def self.project_root(project_id)
    Dir.pwd + "/projects/#{project_id}"
  end

  # Writes the project state to the system so we can resume
  # from errors and prevent having redundant requests.
  #
  def self.write(cache)
    File.write(
      "#{App.project_root(cache[:project_id])}/cache.yml",
      cache.to_yaml
    )
    cache
  end

  def self.working_images_pattern(cache)
    "#{App.project_root(cache[:project_id])}/*.png"
  end

  # Copies the current set of images to the stash folder
  # so we always have a backup of the version before the
  # destructive action.
  #
  def self.stash(cache)
    App.debug " -> Stashing the working images"
    stash_path = App.project_root(cache[:project_id]) + "/stash"
    Dir.mkdir(stash_path) unless Dir.exist?(stash_path)

    system("cp #{App.working_images_pattern(cache)} " \
      "#{stash_path}")
  end

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
      cache = App.load_cache(params["project_id"])

      App.stash(cache)
      App.send(action, cache)
      cache[action] = true
      App.write(cache)

      redirect "/projects/#{cache[:project_id]}"
    end
  end

  get "/projects/:project_id/?" do
    App.debug "Loading Project #{params["project_id"]}"
    @cache = App.load_cache(params["project_id"])

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

    cache = App.load_cache(params["project_id"])
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
