# frozen_string_literal: true

module Actions
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    # Loads existing cache for the :project_id if found,
    # otherwise creates new project folder and cache file.
    #
    def find_or_create_project(form_params)
      App.debug "Submitted: #{form_params.to_s}"

      if (
        form_params["project_id"] && File.exist?(
          "#{App.project_root(form_params["project_id"])}/cache.yml"
        )
      )
        App.debug 'existing project'
        cache = App.
          load_cache_for_project(form_params["project_id"])
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
        App.write_cache(cache)
      end
      cache
    end

    # Copies the current set of images to the stash folder
    # so we always have a backup of the version before the
    # destructive action.
    #
    def stash(cache)
      App.debug " -> Stashing the working images"
      stash_path = App.project_root(cache[:project_id]) + "/stash"
      Dir.mkdir(stash_path) unless Dir.exist?(stash_path)

      system("cp #{App.working_images_pattern(cache)} " \
        "#{stash_path}")
    end

    # Replaces all images found in the project root with a
    # 3x upscaled version.
    #
    # TODO: Maybe refactor as a different grouping of actions
    #       since this affects ALL the images and should
    #       probably skip the stash step.
    #
    def upscale(cache)
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

    # Compresses all images found in the project root.
    #
    # TODO: Maybe refactor as a different grouping of actions
    #       since this affects ALL the images and should
    #       probably skip the stash step.
    #
    def compress(cache)
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
  end
end
