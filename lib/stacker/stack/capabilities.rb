require 'stacker/stack/component'

module Stacker
  class Stack
    class Capabilities < Component

      def local
        @local ||= stack.options.fetch 'Capabilities', {}
      end

      def remote
        @remote ||= client.capabilities
      end

    end
  end
end
