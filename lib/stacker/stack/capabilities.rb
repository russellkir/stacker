require 'stacker/stack/component'

module Stacker
  class Stack
    class Capabilities < Component

      def local
        @local ||= Array(stack.options.fetch 'capabilities', [])
      end

      def remote
        # `capabilities` actually returns a
        # !ruby/array:Aws::Xml::DefaultList, so we convert to a Ruby
        # Array with `map`
        @remote ||= client.capabilities.map(&:self)
      end

    end
  end
end
