# frozen_string_literal: true

module CustomActions
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    # Your actions go here. Name them as custom_*(cache)
    #
    # def custom_whatever(cache)
  end
end
