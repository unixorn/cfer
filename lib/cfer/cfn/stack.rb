module Cfer::Cfn
  class Stack < Cfer::Block
    include Cfer::Cfn

    attr_reader :parameters
    attr_reader :git

    def initialize(parameters = {})
      self[:AWSTemplateFormatVersion] = '2010-09-09'
      self[:Description] = ''
      @parameters = Cfer::Util::ParameterValidator.new(parameters)
      @git = Rugged::Repository.discover('.')

      clean_working_dir = false #@git_status.changed.empty? && @git_status.deleted.empty? && @git_status.added.empty?
      self[:Metadata] = { :Git => { :Rev => @git.head.target_id, :Clean => clean_working_dir } }

      self[:Parameters] = {}
      self[:Mappings] = {}
      self[:Conditions] = {}
      self[:Resources] = {}
      self[:Outputs] = {}
    end

    # Sets the description for this CloudFormation stack
    def description(desc)
      self[:Description] = desc
    end

    # Declares a CloudFormation parameter
    #
    # @param name [String] The parameter name
    # @param options [Hash]
    # @option options [String] :type The type for the CloudFormation parameter
    # @option options [String] :default A value of the appropriate type for the template to use if no value is specified when a stack is created. If you define constraints for the parameter, you must specify a value that adheres to those constraints.
    # @option options [String] :no_echo Whether to mask the parameter value whenever anyone makes a call that describes the stack. If you set the value to `true`, the parameter value is masked with asterisks (*****).
    # @option options [String] :allowed_values An array containing the list of values allowed for the parameter.
    # @option options [String] :allowed_pattern A regular expression that represents the patterns you want to allow for String types.
    # @option options [Number] :max_length An integer value that determines the largest number of characters you want to allow for String types.
    # @option options [Number] :min_length An integer value that determines the smallest number of characters you want to allow for String types.
    # @option options [Number] :max_value A numeric value that determines the largest numeric value you want to allow for Number types.
    # @option options [Number] :min_value A numeric value that determines the smallest numeric value you want to allow for Number types.
    # @option options [String] :description A string of up to 4000 characters that describes the parameter.
    # @option options [String] :constraint_description A string that explains the constraint when the constraint is violated. For example, without a constraint description, a parameter that has an allowed pattern of `[A-Za-z0-9]+` displays the following error message when the user specifies an invalid value:
    #
    #     ```Malformed input-Parameter MyParameter must match pattern [A-Za-z0-9]+```
    #
    #     By adding a constraint description, such as must only contain upper- and lowercase letters, and numbers, you can display a customized error message:
    #
    #     ```Malformed input-Parameter MyParameter must only contain upper and lower case letters and numbers```
    def parameter(name, options = {})
      param = {}
      options.each do |key, v|
        k = key.to_s.camelize.to_sym
        param[k] =
          case k
          when :AllowedValues
            v.join(',')
          when :AllowedPattern
            if v.class == Regexp
              v.source
            else
              v
            end
          when :MaxLength, :MinLength, :MaxValue, :MinValue
            Preconditions.check_type(v, Fixnum, "#{key} must be a numeric value")
            v
          when :Description
            Preconditions.check_argument(v.length <= 4000, "#{key} must be <= 4000 characters")
            v
          end
        param[k] ||= v
      end
      param[:Type] ||= 'String'
      self[:Parameters][name] = param
    end

    def mappings(mappings)
      self[:Mappings] = mappings
    end

    def condition(name, expr)
      self[:Conditions][name] = expr
    end

    # Creates a CloudFormation resource
    # @param name [String] The name of the resource (must be alphanumeric)
    # @param type [String] The type of CloudFormation resource to create.
    # @param options [Hash] Additional attributes to add to the resource block (such as the `UpdatePolicy` for an `AWS::AutoScaling::AutoScalingGroup`)
    def resource(name, type, options = {}, &block)
      Preconditions.check_argument(/[[:alnum:]]+/ =~ name, "Resource name must be alphanumeric")

      clazz = "CferExt::#{type}".split('::').inject(Object) { |o, c| o.const_get c if o && o.const_defined?(c) } || Cfer::Cfn::Resource
      Preconditions.check_argument clazz <= Cfer::Cfn::Resource, "#{type} is not a valid resource type because CferExt::#{type} does not inherit from `Cfer::Cfn::Resource`"

      rc = clazz.new(name, type, options, &block)

      self[:Resources][name] = rc
      rc
    end

    def output(name, value)
      self[:Outputs][name] = {'Value' => value}
    end

    def to_cfn
      to_h.to_json
    end
  end

end
