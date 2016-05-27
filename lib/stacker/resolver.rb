module Stacker
  module Resolvers

    class Resolver

      attr_reader :region, :parameters

      def initialize ref, region
        @ref = ref
        @region = region
      end

      def resolve
        raise NotImplementedError
      end

    end

  end
end
