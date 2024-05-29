# frozen_string_literal: true

# Creates a copy of all the working images in a black
# and white, high-contrast style perhaps referred to as
# "Chiaroscuro".
#
module CustomActions
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def custom_chiarsocurize(cache)
      path_to_images =
        "#{App.project_root(cache[:project_id])}/*.png"
      Dir.glob(path_to_images).each do |path_to_image|
        next if path_to_image.include? "--chiarsocurize"

        parts = path_to_image.split('.')
        output = "#{parts[0]}--chiarsocurize.#{parts[1]}"

        App.debug " -> Chiarsocurizing #{output}"
        system(
          "convert #{path_to_image} " \
          "-brightness-contrast 15x60 -colorspace GRAY #{output}"
        )

        File.delete(path_to_image) if File.exist? path_to_image
      end
    end
  end
end
