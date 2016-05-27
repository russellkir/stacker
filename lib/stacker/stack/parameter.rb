module Stacker
  class Stack
    class Parameter

      extend Memoist

      attr_reader :name, :value, :region

      def initialize name, value, region
        @region = region
        @name = name
        @value = value
      end

      def dependency?
        value.is_a?(Hash)
      end

      def resolved
        dependency? ? resolver.resolve : value
      end
      memoize :resolved

      def to_s
        if dependency?
          value.values.sort.map(&:to_s).join('.')
        else
          value.to_s
        end
      end

      private

      def resolver_class_name
        "Stacker::Resolvers::#{value['Type'] || 'StackOutput'}Resolver"
      end

      def resolver
        resolver_class_name.constantize.new value, region
      end

    end
  end
end
