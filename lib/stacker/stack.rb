require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/hash/slice'
require 'active_support/core_ext/module/delegation'
require 'aws-sdk'
require 'memoist'
require 'stacker/stack/capabilities'
require 'stacker/stack/parameters'
require 'stacker/stack/template'

module Stacker
  class Stack

    class Error < StandardError; end
    class StackPolicyError < Error; end
    class DoesNotExistError < Error; end
    class MissingParameters < Error; end
    class UpToDateError < Error; end

    extend Memoist

    CLIENT_METHODS = %w[
      creation_time
      description
      last_updated_time
      status_reason
    ]

    SAFE_UPDATE_POLICY = <<-JSON
{
  "Statement" : [
    {
      "Effect" : "Deny",
      "Action" : ["Update:Replace", "Update:Delete"],
      "Principal" : "*",
      "Resource" : "*"
    },
    {
      "Effect" : "Allow",
      "Action" : "Update:*",
      "Principal" : "*",
      "Resource" : "*"
    }
  ]
}
JSON

    attr_reader :region, :name, :options

    def initialize region, name, options = {}
      @region, @name, @options = region, name, options
    end

    def client
      @client ||= begin
        res = region.client.describe_stacks(stack_name: name)
        res.stacks.first
      end
    end

    def exists?
      !!client
    end

    def status
      client.stack_status
    end

    delegate *CLIENT_METHODS, to: :client
    memoize *CLIENT_METHODS

    %w[complete failed in_progress].each do |stage|
      define_method(:"#{stage}?") { status =~ /#{stage.upcase}/ }
    end

    def template
      @template ||= Template.new self
    end

    def parameters
      @parameters ||= Parameters.new self
    end

    def capabilities
      @capabilities ||= Capabilities.new self
    end

    def outputs
      @outputs ||= begin
        return {} unless complete?
        Hash[client.outputs.map do |output|
               [ output.output_key, output.output_value ]
             end]
      end
    end

    def create blocking = true
      if exists?
        Stacker.logger.warn 'Stack already exists'
        return
      end

      if parameters.missing.any?
        raise MissingParameters.new(
          "Required parameters missing: #{parameters.missing.join ', '}"
        )
      end

      Stacker.logger.info 'Creating stack'

      params = parameters.resolved.map do |k, v|
        {
          parameter_key: k,
          parameter_value: v
        }
      end

      region.client.create_stack(
        stack_name: name,
        template_body: template.local.to_json,
        parameters: params,
        capabilities: capabilities.local
      )

      wait_while_status 'CREATE_IN_PROGRESS' if blocking
    rescue Aws::CloudFormation::Errors::ValidationError => err
      raise Error.new err.message
    end

    def update options = {}
      options.assert_valid_keys(:blocking, :allow_destructive)

      blocking = options.fetch(:blocking, true)
      allow_destructive = options.fetch(:allow_destructive, false)

      if parameters.missing.any?
        raise MissingParameters.new(
          "Required parameters missing: #{parameters.missing.join ', '}"
        )
      end

      Stacker.logger.info 'Updating stack'

      unless allow_destructive
        # Check for deletes or replacements in the change set
      end

      region.client.execute_change_set(
        change_set_name: change_set,
        stack_name: name
      )

      wait_while_status 'UPDATE_IN_PROGRESS' if blocking
    rescue Aws::CloudFormation::Errors::ValidationError => err
      case err.message
      when /does not exist/
        raise DoesNotExistError.new err.message
      when /No updates/
        raise UpToDateError.new err.message
      else
        raise Error.new err.message
      end
    end

    def describe_change_set
      resp = region.client.describe_change_set(
        change_set_name: change_set,
        stack_name: name
      )
      resp.changes.map do |c|
        rc = c.resource_change
        {
          type: c.type,
          change: {
            logical_resource_id: rc.logical_resource_id,
            action: rc.action,
            details: rc.details,
            replacement: rc.replacement,
            scope: rc.scope
          }
        }
      end
    end

    private

    def change_set
      return @change_set_name if defined? @change_set_name
      @change_set_name = 'generaterandomhere'
      region.client.create_change_set(
        stack_name: name,
        template_body: template.local.to_json,
        parameters: parameters.local.map do |k, v|
          {
            parameter_key: k,
            parameter_value: v
          }
        end,
        capabilities: capabilities.local,
        change_set_name: @change_set_name
      )
      @change_set_name
    end

    def report_status
      case status
      when /_COMPLETE$/
        Stacker.logger.info "#{name} Status => #{status}"
      when /_ROLLBACK_IN_PROGRESS$/
        failure_event = client.events.enum(limit: 30).find do |event|
          event.resource_status =~ /_FAILED$/
        end
        failure_reason = failure_event.resource_status_reason
        if failure_reason =~ /stack policy/
          raise StackPolicyError.new failure_reason
        else
          Stacker.logger.fatal "#{name} Status => #{status}"
          raise Error.new "Failure Reason: #{failure_reason}"
        end
      else
        Stacker.logger.debug "#{name} Status => #{status}"
      end
    end

    def wait_while_status wait_status
      sleep 2 # Give CFN some time to move out of the previous state.
      while flush_cache('status') && status == wait_status
        report_status
        sleep 5
      end
      report_status
    end

  end
end

