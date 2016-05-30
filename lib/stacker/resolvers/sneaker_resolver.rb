require 'stacker/resolvers/resolver'

module Stacker
  module Resolvers

    class SneakerResolver < Resolver

      def resolve
        master_key = ref.fetch('Key')
        secret_path = ref.fetch('Path')
        secret_name = ref.fetch('Name')
        env_vars = "SNEAKER_MASTER_KEY=#{master_key} SNEAKER_S3_PATH=#{secret_path}"
        `#{env_vars} sneaker download #{secret_name} -`
      end

    end

  end
end
