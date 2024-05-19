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

class App < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
  end

  ###########
  ## Config ##
  ############

  def self.project_ids
    Dir.glob('./projects/**').
      map{|path| path.split('/').last}
  end

  # The config for Open AI
  def self.open_ai
    @open_ai ||= OpenAI::Client.new(
      access_token:ENV["OPENAI_API_KEY"],
      request_timeout: 480,
      log_errors: true
    )
  end

  def self.complete?(cache)
    return false unless [
      :project_id, :audio_file_name, :context, :image_model,
      :transcription, :summary, :prompts, :images
    ].all?{ |attr| cache.keys.include? attr }

    puts cache[:images]&.count
    puts cache[:prompts]&.count
    !cache[:images].nil? && !cache[:prompts].nil? &&
      cache[:images]&.count >= cache[:prompts]&.count
  end

  def self.optimized?(cache)
    !cache[:optimized].nil? && cache[:optimized] == true
  end

  def self.dalle_models
    [ "dall-e-2", "dall-e-3" ]
  end

  # Color map for generating image variants with imagemagick
  def self.colors
    {
      "brown" => "#573320",
      "red" => "#910E0E",
      "green" => "#406F37",
      "navy" => "#102255",
      "gray" => "#75797B",
    }
  end

  # The prompt wrapper for the call to DALL-E
  def self.sketch_prompt(prompt, cache)
    "I NEED to test how the tool works with extremely "
    "simple prompts. DO NOT add any detail, just use it AS-IS: " \
    "Please create a minimalist, campy, black and white pencil " \
    "drawing, of \"#{prompt}\". " \
    "#{' Also consider this overall setting: ' +
      cache[:context] + '. ' if !cache[:context].nil? }" \
    "This image is for someone who CANNOT read."
  end

  # The number of prompts to generate
  def self.prompt_count
    40
  end

  def self.load_cache(project_id)
    YAML.load(
      File.open("#{App.project_root(project_id)}/cache.yml")
    )
  end

  def self.find_or_create_project(form_params)
    puts "Submitted: #{form_params.to_s}"

    if (
      form_params["project_id"] && File.exist?(
        "#{App.project_root(form_params["project_id"])}/cache.yml"
      )
    )
      puts 'existing project'
      cache = App.load_cache(form_params["project_id"])
    else
      puts 'new project'
      cache = {}
      cache[:project_id] = SecureRandom.urlsafe_base64.
        gsub(/[^a-zA-Z\d]/, '').slice(0..6).downcase
      if form_params["audio"]
        cache[:audio_file_name] = form_params["audio"]["filename"]
      end
      if form_params["context"] && form_params["context"] != ""
        cache[:context] = form_params["context"]
      end
      cache[:image_model] = form_params["image_model"]
      unless Dir.exist?(App.project_root(cache[:project_id]))
        Dir.mkdir(App.project_root(cache[:project_id]))
      end
      App.write(cache)
    end
    cache
  end

  # Replaces all images found in "project_root" with 3x upscaled version
  def self.upscale(cache)
    Dir.glob("#{App.project_root(cache[:project_id])}/*.png").each do |path_to_image|
      next if path_to_image.include? "--upscaled"

      parts = path_to_image.split('.')
      output = "#{parts[0]}-upscaled.#{parts[1]}"

      puts "Upscaling to #{output}"
      system(
        "./realesrgan-ncnn-vulkan " \
        "-s 3 -v " \
        "-i #{path_to_image} " \
        "-o #{parts[0]}--upscaled.#{parts[1]}"
      )

      File.delete(path_to_image) if File.exist? path_to_image
    end
  end

  # Adds "feathered edge" to all images found in "project_root"
  def self.feather(cache)
    Dir.glob("#{App.project_root(cache[:project_id])}/*.png").each do |path_to_image|
      next if path_to_image.include? "--feathered"

      parts = path_to_image.split('.')
      output = "#{parts[0]}--feathered.#{parts[1]}"

      puts "Feathering #{output}"
      system(
        "convert #{path_to_image} ./bgw_edge.png -alpha off " \
        "-compose CopyOpacity " \
        "-composite #{output}"
      )

      File.delete(path_to_image) if File.exist? path_to_image
    end
  end

  def self.normalize(cache)
    Dir.glob("#{App.project_root(cache[:project_id])}/*.png").each do |path_to_image|
      next if path_to_image.include? "--normalized"

      parts = path_to_image.split('.')
      output = "#{parts[0]}--normalized.#{parts[1]}"

      puts "Normalizing #{output}"
      system(
        "convert #{path_to_image} " \
        "-brightness-contrast 15x60 -colorspace GRAY #{output}"
      )

      File.delete(path_to_image) if File.exist? path_to_image
    end
  end

  def self.compress(cache)
    Dir.glob("#{App.project_root(cache[:project_id])}/**/*.png").each do |path_to_image|
      next if path_to_image.include? "--compressed"

      parts = path_to_image.split('.')
      output = "#{parts[0]}--compressed.#{parts[1]}"

      puts "Compressing #{output}"
      system(
        "pngquant -f --speed 1 --strip #{path_to_image} " \
        "--ext --compressed.png"
      )

      File.delete(path_to_image) if File.exist? path_to_image
    end
  end

  # Creates a clone of the image for each App.color entry
  def self.colorize(cache)
    App.colors.each do |color_name, color_value|
      path = App.project_root(cache[:project_id]) +
        "/#{color_name}"
      Dir.mkdir(path) unless Dir.exist?(path)
      Dir.glob(
        "#{App.project_root(cache[:project_id])}/*.png"
      ).each do |path_to_image|
        next if path_to_image.include? "--#{color_name}"

        parts = path_to_image.split('.')
        output = "#{parts[0]}--#{color_name}.#{parts[1]}"

        puts "Creating #{color_name} clone of #{path_to_image}"
        system(
          "convert #{path_to_image} " \
          "-set colorspace RGB -fuzz 85% " \
          "-fill '#{color_value}' -opaque black #{output}"
        )
        system("mv #{output} #{path}/")
      end
    end
  end

  # Converts audio file to text and writes it to
  # the cache object, returning it
  def self.transcribe(file, cache)
    puts "self.transcribe"
    unless cache[:transcription]
      step1_response = App.open_ai.audio.translate(
        parameters: {
          model: "whisper-1",
          file: ,
        }
      )
      cache[:transcription] = step1_response["text"]

      puts "Transcription Complete"
      App.write(cache)
    end
    cache
  end

  # Converts transcribed text to a number of prompts and
  # writes them to the cache object, returning it
  def self.generate_prompts(cache)
    puts "self.generate_prompts"
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
              "#{App.prompt_count.to_s} stand-alone 'prompts' " \
              "optimized for DALL-E image generation. They " \
              "should be one short sentence each." \
              "#{' Keep in mind ' + cache[:context] + "." if !cache[:context].nil?} " \
              " Produce a JSON array of strings under the " \
              "attribute name 'prompts'. The total character " \
              "count of all prompts combined should be less than " \
              "or equal to 1000:\n\n#{cache[:transcription]}."
          }],
          temperature: 0.7,
        }
      )

      content =
        step2_response["choices"].first["message"]["content"]

      cache[:prompts] = JSON.parse(content)["prompts"]

      puts "Prompt Extraction Complete"
      App.write(cache)
    end
    cache
  end

  # Converts prompts to a short summary and writes
  # is to the cache object, returning it
  def self.summarize(cache)
    puts "self.summarize"
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
            content: "Please summarize this text to 3 " \
              "short sentences: #{cache[:prompts].join(' ')}. " \
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

      puts "Summary Generation Complete"
      App.write(cache)
    end
    cache
  end

  # Converts prompts to a images and writes
  # is to the cache object, returning it
  def self.generate_images(cache)
    puts "self.generate_images"
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
        puts "Generating image for: #{prompt}"

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
        puts "Image Generated:"
        puts cache_item

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

  # Todays date as a string, (i.e. "2024-05-17")
  def self.today
    Time.now.strftime "%Y-%m-%d"
  end

  # Returns the full path to the root folder for
  # the :project_id value given
  def self.project_root(project_id)
    Dir.pwd + "/projects/#{project_id}"
  end

  # Writes the YAML state to the system to prevent redundant requests
  def self.write(cache)
    File.write(
      "#{App.project_root(cache[:project_id])}/cache.yml",
      cache.to_yaml
    )
    cache
  end

  ############
  ## Routes ##
  ############

  get '/' do
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
    puts "hit /"
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
    rescue StandardError => e
      "<h3 style='color: #{App.colors["red"]};'>#{e.message}</h3>"
    end
  end

  get '/projects/:project_id/images' do
    puts "hit projects/:project_id/images"
    cache = App.load_cache(params["project_id"])
    if cache
      @images = Dir.glob(
        App.project_root(params["project_id"]) + "/**/*.png"
      )
    end
    slim :project_images
  end

  post '/projects/:project_id/optimize' do
    puts "hit projects/:project_id/optimize"
    cache = App.load_cache(params["project_id"])

    # Source image steps here
    App.normalize(cache)
    App.upscale(cache)

    # Image replication steps from here
    App.colorize(cache)

    # Polish and clean up steps here
    App.feather(cache)
    App.compress(cache)

    cache[:optimized] = true
    App.write(cache)
  end

  get '/projects/:project_id' do
    puts "hit projects/:project_id"
    @cache = App.load_cache(params["project_id"])

    if @cache
      @images = Dir.glob(
        App.project_root(params["project_id"]) + "/**/*.png"
      )
    end
    slim :project
  end

  get '/projects/:project_id/:image_file_name' do
    path_to_image =
      "/#{params["project_id"]}/#{params["image_file_name"]}"
    identifier = params["image_file_name"].split("--").first

    cache = App.load_cache(params["project_id"])
    if (
      cache && cache[:images] &&
      cache[:images].any?{|item| item[:path].
        include? identifier }
    )
      send_file(
        App.project_root(params["project_id"]) +
          "/#{params["image_file_name"]}",
        :type => :png
      )
    else
      puts 'File path not found in cache'
      ""
    end
  end

  run!
end
