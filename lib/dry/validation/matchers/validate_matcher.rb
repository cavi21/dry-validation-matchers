module Dry::Validation::Matchers
  class ValidateMatcher

    DEFAULT_TYPE = :string
    TYPE_ERRORS = {
      string: {
        test_value: "str",
        message: "must be a string",
      },
      integer: {
        test_value: 43,
        message: "must be an integer",
      },
      float: {
        test_value: 41.5,
        message: "must be a float",
      },
      decimal: {
        test_value: BigDecimal("41.5"),
        message: "must be a decimal",
      },
      bool: {
        test_value: false,
        message: "must be a boolean",
      },
      date: {
        test_value: Date.new(2011, 1, 2),
        message: "must be a date",
      },
      time: {
        test_value: Time.new(2011, 1, 2, 2, 33),
        message: "must be a time",
      },
      date_time: {
        test_value: DateTime.new(2011, 5, 1, 2, 3, 4),
        message: "must be a date time",
      },
      array: {
        test_value: [1, 3, 5],
        message: "must be a array",
      },
      hash: {
        test_value: {hello: "there"},
        message: "must be a hash",
      },
    }

    def initialize(attr, acceptance)
      @attr = attr
      @acceptance = acceptance
      @type = DEFAULT_TYPE
      @value_rules = []
      @macro_usage_params = []
      @check_filled = false
      @check_macro = false
    end

    def description
      @desc = []
      @desc << "validate for #{acceptance} `#{attr}`"

      validation_details_message = []
      validation_details_message << "filled with #{type}" if check_filled
      validation_details_message << "macro usage `#{macro_usage_params.to_s}`" if check_macro

      unless validation_details_message.empty?
        @desc << " ("
        @desc << validation_details_message.join("; ")
        @desc << ")"
      end

      @desc << " exists"
      @desc.join
    end

    def failure_message
      @desc = []
      @desc << "be missing validation for #{acceptance} `#{attr}`"

      validation_details_message = []
      validation_details_message << "filled with #{type}" if check_filled
      validation_details_message << "macro usage `#{macro_usage_params.to_s}`" if check_macro

      unless validation_details_message.empty?
        @desc << " ("
        @desc << validation_details_message.join("; ")
        @desc << ")"
      end

      @desc.join
    end

    def matches?(schema_or_schema_class)
      if schema_or_schema_class.is_a?(Dry::Validation::Contract)
        schema = schema_or_schema_class
      elsif schema_or_schema_class.is_a?(Class) &&
        schema_or_schema_class.ancestors.include?(Dry::Validation::Contract)

        schema = schema_or_schema_class.new
      else
        fail(
          ArgumentError,
          "must be a schema instance or class; got #{schema_or_schema_class.inspect} instead"
        )
      end

      check_required_or_optional!(schema) &&
        check_filled!(schema) &&
        check_filled_with_type!(schema) &&
        check_value!(schema) &&
        check_macro_usage!(schema)
    end

    def filled(type=DEFAULT_TYPE)
      @check_filled = true
      @type = type
      self
    end

    def value(value_rules)
      @value_rules = value_rules
      self
    end

    def macro_use?(macro_params)
      @check_macro = true
      @macro_usage_params = macro_params
      self
    end

    private

    attr_reader :attr,
      :acceptance,
      :type,
      :value_rules,
      :macro_usage_params,
      :check_filled,
      :check_macro

    def check_required_or_optional!(schema)
      case acceptance
      when :required
        result = schema.({})
        attr_errors = get_attr_errors(result)
        attr_errors.respond_to?('each') && attr_errors.any? { |msg| msg.predicate == :key? }
      else
        result = schema.({})
        result.errors[attr].nil?
      end
    end

    def check_filled!(schema)
      return true if !check_filled

      result = schema.(attr => nil)
      attr_errors = get_attr_errors(result)
      if result.errors[attr].nil? ||
          !attr_errors.any? { |msg| msg.predicate == :filled? }
        return false
      end
      true
    end

    def check_filled_with_type!(schema)
      return true if !check_filled
      result = schema.(attr => TYPE_ERRORS[type][:test_value])
      error_messages = result.errors[attr]
      return true if error_messages.nil?
      # Message not allowed are all the type_error_messages that are not the
      # expected type. Any other message is accepted (like "size cannot be less than 20")
      unallowed_errors = type_error_messages - [TYPE_ERRORS[type][:message]]
      # We check if error_messages intersect with the unallowed_errors.
      # if intersection is empty, then the check is passed.
      (error_messages & unallowed_errors).empty?
    end

    def check_value!(schema)
      value_rules.map do |rule|
        method_name = :"check_value_#{rule[0]}!"
        return true if !self.class.private_method_defined?(method_name)
        send(method_name, schema, rule)
      end.none? {|result| result == false}
    end

    def check_value_included_in!(schema, rule)
      predicate = rule[0]
      allowed_values = rule[1]

      invalid_for_expected_values = allowed_values.map do |v|
        result = schema.(attr => v)
        error_messages = result.errors[attr]
        error_messages.respond_to?('each') && error_messages.grep(/must be one of/).any?
      end.any? {|result| result == true}
      return false if invalid_for_expected_values

      value_outside_required = allowed_values.sample.to_s + SecureRandom.hex(2)
      result = schema.(attr => value_outside_required)
      error_messages = result.errors[attr]
      return false if error_messages.nil?
      return true if error_messages.grep(/must be one of/).any?
      false
    end

    def check_value_min_size!(schema, rule)
      predicate = rule[0]
      min_size = rule[1]

      expected_error_message = "size cannot be less than #{min_size}"

      result = schema.(attr => "a" * (min_size+1))
      error_messages = result.errors[attr]
      no_error_when_over = error_messages.nil? ||
        !error_messages.include?(expected_error_message)

      result = schema.(attr => "a" * (min_size))
      error_messages = result.errors[attr]
      no_error_when_exact = error_messages.nil? ||
        !error_messages.include?(expected_error_message)

      result = schema.(attr => "a" * (min_size-1))
      error_messages = result.errors[attr]
      error_when_below = (min_size-1).zero? ||
        !error_messages.nil? &&
        error_messages.include?(expected_error_message)

      no_error_when_over && no_error_when_exact && error_when_below
    end

    def check_value_max_size!(schema, rule)
      predicate = rule[0]
      max_size = rule[1]

      expected_error_message = "size cannot be greater than #{max_size}"

      result = schema.(attr => "a" * (max_size+1))
      error_messages = result.errors[attr]
      error_when_over = error_messages.respond_to?('each') &&
        error_messages.include?(expected_error_message)

      result = schema.(attr => "a" * (max_size))
      error_messages = result.errors[attr]
      no_error_when_within = error_messages.nil? ||
        !error_messages.include?(expected_error_message)

      error_when_over && no_error_when_within
    end

    def check_macro_usage!(schema)
      return true if macro_usage_params.empty?

      is_present = false

      schema.rules.each do |obj|
        next if obj.keys.first != attr

        value = if macro_usage_params.is_a?(Hash) && obj.macros.flatten.count > 1
                  obj.macros.to_h.map { |k, v| [k, v.first] }.to_h
                else
                  obj.macros.flatten.first
                end

        if value == macro_usage_params
          is_present = true
          break
        end
      end

      is_present
    end

    def type_error_messages
      type_error_messages = []
      TYPE_ERRORS.each_pair do |type, hash|
        type_error_messages << hash[:message]
      end
      type_error_messages
    end

    def get_attr_errors(result)
      result.errors.select do |msg|
        Dry::Schema::Path[msg.path].include?(Dry::Schema::Path[attr])
      end
    end
  end
end
