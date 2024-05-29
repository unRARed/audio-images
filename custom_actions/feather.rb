# frozen_string_literal: true

# Creates a copy of all the working images adding a
# "feathered edge" (fading to transparency).
#
module CustomActions
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def custom_feather(cache)
      Dir.glob(App.working_images_pattern(cache)).each do |path|
        next if path.include? "--feathered"
        if !path.include? "--upscaled"
          raise DependentActionError,
            "Images must be upscaled before feathering"
        end

        parts = path.split('.')
        output = "#{parts[0]}--feathered.#{parts[1]}"

        App.debug " -> Feathering #{output}"
        system(
          "convert #{path} ./bgw_edge.png -alpha off " \
          "-compose CopyOpacity " \
          "-composite #{output}"
        )

        File.delete(path) if File.exist? path
      end
    end
  end
end
