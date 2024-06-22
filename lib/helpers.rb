# frozen_string_literal: true

module Helpers
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    # Allows hiding or showing the debug information by
    # settings the DEBUG environment variable at runtime.
    #
    #   Example: `DEBUG=1 ruby app.rb`
    #
    def debug(msg)
      return unless !ENV["DEBUG"].nil?

      count = msg.length
      divider = []
      [msg.length, 79].min.times{ divider << "-" }
      puts divider.join
      puts "DEBUG: #{msg}"
      puts divider.join
    end

    # Returns the full path to the root folder for
    # the :project_id value given
    #
    #   Example: /Users/some_user/audio-images/projects/2fgdaf"
    #
    def project_root(project_id)
      Dir.pwd + "/projects/#{project_id}"
    end

    def project_name(cache)
      audio = cache[:audio_file_name].
        tr(" ", "-")&.gsub(/[^0-9a-z-\.]/i, '')
      context = cache[:context]&.
        tr(" ", "-")&.gsub(/[^0-9a-z-]/i, '')
      "#{cache[:project_id]} -> " \
        "#{audio} #{'(' + context + ')' if context}"[0..60]
    end

    # Loads, reads and parses /projects/:project_id/cache.yml
    # for keeping track of project-specific metadata.
    #
    def load_cache_for_project(project_id)
      YAML.load(
        File.open("#{App.project_root(project_id)}/cache.yml")
      )
    end

    # Writes the project state to the system so we can resume
    # from errors and prevent having redundant requests.
    #
    def write_cache(cache)
      File.write(
        "#{App.project_root(cache[:project_id])}/cache.yml",
        cache.to_yaml
      )
      cache
    end

    def working_images_pattern(cache)
      "#{App.project_root(cache[:project_id])}/*.png"
    end

    def actions
      names = []
      names << :upscale if !ENV["GPU"].nil?
      names << :compress
      names + self.methods.
          select{|name| name.to_s.start_with?("custom_") }
    end

    def available_actions(cache)
      available_actions = []
      App.actions.each do |action|
        unless !cache[action].nil? && cache[action] == true
          available_actions << action
        end
      end
      available_actions
    end

    def project_names
      ids = Dir.glob('./projects/**').
        map{|path| path.split('/').last}
      for_select = []
      ids.each do |id|
        project = App.load_cache_for_project(id)
        for_select << [id, App.project_name(project)]
      end
      for_select
    end

    def complete?(cache)
      return false unless [
        :project_id, :audio_file_name, :image_model,
        :transcription, :summary, :prompts, :images
      ].all?{ |attr| cache.keys.include? attr }

      # App.debug cache[:images]&.count
      # App.debug cache[:prompts]&.count
      !cache[:images].nil? && !cache[:prompts].nil? &&
        cache[:images]&.count >= cache[:prompts]&.count
    end
  end
end
