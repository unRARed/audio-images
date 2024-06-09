# frozen_string_literal: true

# Creates a copy of all the working images, colorized per the
# mapping hash (COLORS).
#
#   This is an example of a custom action.
#   Create your own from ./custom_actions/starter.rb
#
module CustomActions
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    COLORS = {
      "brown" => "#573320",
      "red" => "#910E0E",
      "green" => "#406F37",
      "navy" => "#102255",
      "gray" => "#75797B",
    }

    COLORS.each do |color_name, color_value|
      define_method "color_#{color_name}" do
        COLORS[color_name]
      end

      define_method "custom_#{color_name}" do |cache|
        color_path = App.project_root(cache[:project_id]) +
          "/stash/#{color_name}"
        Dir.mkdir(color_path) unless Dir.exist?(color_path)

        Dir.glob(App.working_images_pattern(cache)).each do |path|
          next if path.include? "--#{color_name}"

          parts = path.split('.')
          output = "#{parts[0]}--#{color_name}.#{parts[1]}"

          App.debug " -> Creating #{color_name} clone of #{path}"
          system(
            "convert #{path} " \
            "-set colorspace RGB -fuzz 85% " \
            "-fill '#{color_value}' -opaque black #{output}"
          )
          system("mv #{output} #{color_path}")
        end
      end
    end
  end
end
