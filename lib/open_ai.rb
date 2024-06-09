# frozen_string_literal: true

module OpenAi
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    # The config for the Open AI Library. Assumes the
    # environment variable "OPENAI_API_KEY" is set.
    #
    def open_ai
      @open_ai ||= OpenAI::Client.new(
        access_token:ENV["OPENAI_API_KEY"],
        request_timeout: 480,
        log_errors: true
      )
    end

    # Converts audio file to text and writes it to
    # the cache object, returning it
    def transcribe(file, cache)
      App.debug "Transcribing Audio"
      unless cache[:transcription]
        step1_response = App.open_ai.audio.translate(
          parameters: {
            model: "whisper-1",
            file: ,
          }
        )
        cache[:transcription] = step1_response["text"]

        App.debug " -> Audio Transcribed"
        App.write_cache(cache)
      end
      cache
    end

    # Converts transcribed text to a number of prompts and
    # writes them to the cache object, returning it
    def generate_prompts(cache)
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

        App.debug " -> Prompts Generated"
        App.write_cache(cache)
      end
      cache
    end

    # Converts prompts to a short summary and writes
    # is to the cache object, returning it
    def summarize(cache)
      App.debug "Summarizing Transcription"
      unless cache[:transcription]
        raise ArgumentError, "No transcription to summarize"
      end
      # Step 3: Summarize the transcription
      unless cache[:summary]
        step3_response = App.open_ai.chat(
          parameters: {
            model: "gpt-4o",
            # model: "gpt-3.5-turbo", # good enough?
            response_format: { type: "json_object" },
            messages: [{
              role: "user",
              content: "Please summarize this text into " \
                "one paragraph: #{cache[:transcription].join(' ')}. " \
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

        App.debug " -> Transcription Summarized"
        App.write_cache(cache)
      end
      cache
    end

    # Converts prompts to a images and writes
    # is to the cache object, returning it
    def generate_images(cache)
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
          App.debug " -> Image Generated:"
          App.debug " -> " + cache_item.to_s

          URI.open(data["url"]) do |image|
            File.open("#{App.project_root(
              cache[:project_id])}/#{image_path}", "wb"
            ) do |file|
              file.write(image.read)
            end
          end
          cache[:images] << cache_item

          App.write_cache(cache)
        end
      end
      cache
    end

    # Possible Open AI image generation models the user
    # can choose from.
    def dalle_models
      [ "dall-e-2", "dall-e-3" ]
    end

    #############
    ## Helpers ##
    #############

    # The prompt wrapper for the call to DALL-E. It should create
    # an image specific to the prompt given and consider the
    # :style in the cache object (if supplied).
    #
    # NOTE: Considering the :context and/or the :summary here seems
    #       to cause DALL-E to become liberal with the use of text
    #       in the images it generates.
    #
    def sketch_prompt(prompt, cache)
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
  end
end
