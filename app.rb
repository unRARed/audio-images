#!/usr/bin/env ruby -I ../lib -I lib
# frozen_string_literal: true

require "sinatra/base"
require "sinatra/reloader"
require "openai"
require "open-uri"
require "yaml"
require "byebug"
require "fileutils"

class App < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
  end

  def self.root
    Dir.pwd + "/#{App.today}"
  end

  def self.write(cache)
    File.write("#{App.root}/cache.yml", cache.to_yaml)
  end

  def self.sketch_prompt(detail)
    "Please create a minimalist, black and white pencil " \
    "drawing, of \"#{detail}\". " \
    "This image is for someone who CANNOT read."
  end

  def self.beat_count
    2
  end

  def self.today
    Time.now.strftime "%Y-%m-%d"
  end

  def self.open_ai
    @open_ai ||= OpenAI::Client.new(
      access_token:ENV["OPENAI_API_KEY"],
      request_timeout: 480,
      log_errors: true
    )
  end

  get '/upscale' do
    Dir.glob("#{App.root}/*.png").each do |path_to_image|
      parts = path_to_image.split('.')
      output = "#{parts[0]}-upscaled.#{parts[1]}"

      puts "Upscaling to #{output}"
      system(
        "cd upscaler && ./realesrgan-ncnn-vulkan " \
        "-s 3 -v " \
        "-i #{path_to_image} " \
        "-o #{parts[0]}--upscaled.#{parts[1]}"
      )
    end
  end

  get '/' do
    "<form action='/' method='post' \
      enctype='multipart/form-data'>" \
      "<p>Upload file (must be 25mb or less)</p>" \
      "<input type='text' name='context' /><br>" \
      "<input type='file' name='audio' accept='.mp3,audio/*' />" \
      "<br><input type='submit' value='Upload Audio' />" \
    "</form>"
  end

  # Takes an audio file and asks OpenAI to do the following:
  #
  #   - Determine Transcription
  #   - Generate a number of "Beats" from the Transcription
  #   - Generate an image for each Beat
  #
  post '/' do
    begin
      puts "Submitted: #{params.to_s}"
      context = params["context"]

      Dir.mkdir(App.root) unless Dir.exist?(App.root)

      if File.exist? "#{App.root}/cache.yml"
        @cache = YAML.load(File.open("#{App.root}/cache.yml"))
      else
        @cache = {}
        App.write(@cache)
      end

      # Step 1: Convert the audio to text
      unless @cache[:transcription]
        step1_response = App.open_ai.audio.translate(
          parameters: {
            model: "whisper-1",
            file: File.open(params["audio"]["tempfile"], "rb"),
          }
        )
        @cache[:transcription] = step1_response["text"]

        App.write(@cache)
      end
      puts "Transcription Complete"

      # Step 2: Convert the text to beats
      unless @cache[:beats]
        step2_response = App.open_ai.chat(
          parameters: {
            model: "gpt-4o",
            # model: "gpt-3.5-turbo", # good enough?
            response_format: { type: "json_object" },
            messages: [{
              role: "user",
              content: "Please consider this full text following " \
                "the colon and concisely summarize 40 stand-alone " \
                "'beats' (one short sentence each) from it." \
                "#{' Keep in mind ' + context + ". " if context} " \
                "Produce a JSON array of strings under the " \
                "attribute name 'beats'. The total character " \
                "count of all beats combined should be less than " \
                "or equal to 600:\n\n#{@cache[:transcription]}."
            }],
            temperature: 0.7,
          }
        )

        content =
          step2_response["choices"].first["message"]["content"]

        @cache[:beats] = JSON.parse(content)["beats"]

        App.write(@cache)
      end
      puts "Beat Extraction Complete"

      # Step 3: Summarize the beats
      unless @cache[:summary]
        step3_response = App.open_ai.chat(
          parameters: {
            model: "gpt-4o",
            # model: "gpt-3.5-turbo", # good enough?
            response_format: { type: "json_object" },
            messages: [{
              role: "user",
              content: "Please summarize this text to 3 " \
                "short sentences: #{@cache[:beats].join(' ')}. " \
                "#{'Keep in mind ' + context + ". " if context} " \
                "Please produce the response as JSON under the " \
                "attribute name 'summary'."
            }],
            temperature: 0.7,
          }
        )

        content =
          step3_response["choices"].first["message"]["content"]

        @cache[:summary] = JSON.parse(content)["summary"]
        App.write(@cache)
      end
      puts "Summary Generation Complete"

      # Step 4: Generate the images
      @cache[:images] ||= []
      generated_images = Dir.glob("#{App.root}/*.png")

      unless generated_images.length >= @cache[:beats].length
        @cache[:beats].each_with_index do |beat, i|
          image_path = App.today + "/" + ("%03d" % (i+1)) +
            "_" + beat.gsub(" ", "-").
            gsub(/[^a-zA-Z\-]/, '') + ".png"
          puts "Generating #{image_path}"

          next if @cache[:images].include? image_path

          image_response = App.open_ai.images.generate(
            parameters: {
              model: "dall-e-3", # 0.04 or 0.08 (HD)
              # model: "dall-e-2",
              size: "1024x1024",
              quality: "standard",
              prompt: App.sketch_prompt(beat)
            }
          )

          next unless image_url =
            image_response["data"]&.first["url"]

          URI.open(image_url) do |image|
            File.open(image_path, "wb") do |file|
              file.write(image.read)
            end
          end
          @cache[:images] << image_path

          App.write(@cache)

          puts "Image Generated:"
          puts image_path
        end
      end

      # Step 5: Upscale the images
      Dir.glob("#{App.root}/*.png").each do |path_to_image|
        next if path_to_image.include? "--upscaled"

        parts = path_to_image.split('.')
        output = "#{parts[0]}-upscaled.#{parts[1]}"

        puts "Upscaling to #{output}"
        system(
          "cd upscaler && ./realesrgan-ncnn-vulkan " \
          "-s 3 -v " \
          "-i #{path_to_image} " \
          "-o #{parts[0]}--upscaled.#{parts[1]}"
        )

        File.delete(path_to_image) if File.exist? path_to_image
      end
    rescue StandardError => e
      byebug
    end
  end

  run!
end
