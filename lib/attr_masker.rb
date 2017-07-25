# (c) 2017 Ribose Inc.
#

# Adds attr_accessors that mask an object's attributes
module AttrMasker
  autoload :Version, 'attr_masker/version'

  require 'attr_masker/railtie' if defined?(Rails)
  def self.extended(base) # :nodoc:
    base.class_eval do

      # Only include the dangerous instance methods during the Rake task!
      include InstanceMethods
      attr_writer :attr_masker_options
      @attr_masker_options, @masker_attributes = {}, {}
    end
  end

  # Generates attr_accessors that mask attributes transparently
  #
  # Options (any other options you specify are passed to the masker's mask
  # methods)
  #
  #   :attribute        => The name of the referenced masker attribute. For example
  #                        <tt>attr_accessor :email, :attribute => :ee</tt> would generate an
  #                        attribute named 'ee' to store the masker email. This is useful when defining
  #                        one attribute to mask at a time or when the :prefix and :suffix options
  #                        aren't enough. Defaults to nil.
  #
  #   :prefix           => A prefix used to generate the name of the referenced masker attributes.
  #                        For example <tt>attr_accessor :email, :password, :prefix => 'crypted_'</tt> would
  #                        generate attributes named 'crypted_email' and 'crypted_password' to store the
  #                        masker email and password. Defaults to 'masker_'.
  #
  #   :suffix           => A suffix used to generate the name of the referenced masker attributes.
  #                        For example <tt>attr_accessor :email, :password, :prefix => '', :suffix => '_masker'</tt>
  #                        would generate attributes named 'email_masker' and 'password_masker' to store the
  #                        masker email. Defaults to ''.
  #
  #   :key              => The maskion key. This option may not be required if you're using a custom masker. If you pass
  #                        a symbol representing an instance method then the :key option will be replaced with the result of the
  #                        method before being passed to the masker. Objects that respond to :call are evaluated as well (including procs).
  #                        Any other key types will be passed directly to the masker.
  #
  #   :encode           => If set to true, attributes will be encoded as well as masker. This is useful if you're
  #                        planning on storing the masker attributes in a database. The default encoding is 'm' (base64),
  #                        however this can be overwritten by setting the :encode option to some other encoding string instead of
  #                        just 'true'. See http://www.ruby-doc.org/core/classes/Array.html#M002245 for more encoding directives.
  #                        Defaults to false unless you're using it with ActiveRecord, DataMapper, or Sequel.
  #
  #   :marshal          => If set to true, attributes will be marshaled as well as masker. This is useful if you're planning
  #                        on masking something other than a string. Defaults to false unless you're using it with ActiveRecord
  #                        or DataMapper.
  #
  #   :marshaler        => The object to use for marshaling. Defaults to Marshal.
  #
  #   :dump_method      => The dump method name to call on the <tt>:marshaler</tt> object to. Defaults to 'dump'.
  #
  #   :load_method      => The load method name to call on the <tt>:marshaler</tt> object. Defaults to 'load'.
  #
  #   :masker        => The object to use for masking. Defaults to Masker.
  #
  #   :mask_method   => The mask method name to call on the <tt>:masker</tt> object. Defaults to 'mask'.
  #
  #   :if               => Attributes are only masker if this option evaluates to true. If you pass a symbol representing an instance
  #                        method then the result of the method will be evaluated. Any objects that respond to <tt>:call</tt> are evaluated as well.
  #                        Defaults to true.
  #
  #   :unless           => Attributes are only masker if this option evaluates to false. If you pass a symbol representing an instance
  #                        method then the result of the method will be evaluated. Any objects that respond to <tt>:call</tt> are evaluated as well.
  #                        Defaults to false.
  #
  # You can specify your own default options
  #
  #   class User
  #     # now all attributes will be encoded and marshaled by default
  #     attr_masker_options.merge!(:encode => true, :marshal => true, :some_other_option => true)
  #     attr_masker :configuration, :key => 'my secret key'
  #   end
  #
  #
  # Example
  #
  #   class User
  #     attr_masker :email, :credit_card, :key => 'some secret key'
  #     attr_masker :configuration, :key => 'some other secret key', :marshal => true
  #   end
  #
  #   @user = User.new
  #   @user.masker_email # nil
  #   @user.email? # false
  #   @user.email = 'test@example.com'
  #   @user.email? # true
  #   @user.masker_email # returns the masker version of 'test@example.com'
  #
  #   @user.configuration = { :time_zone => 'UTC' }
  #   @user.masker_configuration # returns the masker version of configuration
  #
  #   See README for more examples
  def attr_masker(*attributes)
    options = {
      :if               => true,
      :unless           => false,
      :encode           => false,
      :column_name      => nil,
      :marshal          => false,
      :marshaler        => Marshal,
      :dump_method      => 'dump',
      :load_method      => 'load',
      :masker           => AttrMasker::Masker,
      :mask_method      => 'mask',
    }.merge!(attr_masker_options).merge!(attributes.last.is_a?(Hash) ? attributes.pop : {})

    attributes.each do |attribute|
      masker_attribute_name = (options[:attribute] ? options[:attribute] : [options[:prefix], attribute, options[:suffix]].join).to_sym
      masker_attributes[attribute.to_sym] = options.merge(:attribute => masker_attribute_name)
    end
  end

  # Default options to use with calls to <tt>attr_masker</tt>
  # XXX:Keep
  #
  # It will inherit existing options from its superclass
  def attr_masker_options
    @attr_masker_options ||= superclass.attr_masker_options.dup
  end

  # Checks if an attribute is configured with <tt>attr_masker</tt>
  # XXX:Keep
  #
  # Example
  #
  #   class User
  #     attr_accessor :name
  #     attr_masker :email
  #   end
  #
  #   User.attr_masker?(:name)  # false
  #   User.attr_masker?(:email) # true
  def attr_masker?(attribute)
    masker_attributes.has_key?(attribute.to_sym)
  end

  # masks a value for the attribute specified
  # XXX:modify
  #
  # Example
  #
  #   class User
  #     attr_masker :email
  #   end
  #
  #   masker_email = User.mask(:email, 'test@example.com')
  def mask(attribute, value, options = {})
    options = masker_attributes[attribute.to_sym].merge(options)
    # if options[:if] && !options[:unless] && !value.nil? && !(value.is_a?(String) && value.empty?)
    if options[:if] && !options[:unless]
      value = options[:marshal] ? options[:marshaler].send(options[:dump_method], value) : value.to_s
      # masker_value = options[:masker].send(options[:mask_method], options.merge!(:value => value))
      masker_value = options[:masker].send(options[:mask_method], options.merge!(:value => value))
      masker_value
    else
      value
    end
  end

  # Contains a hash of masker attributes with virtual attribute names as keys
  # and their corresponding options as values
  # XXX:Keep
  #
  # Example
  #
  #   class User
  #     attr_masker :email, :key => 'my secret key'
  #   end
  #
  #   User.masker_attributes # { :email => { :attribute => 'masker_email', :key => 'my secret key' } }
  def masker_attributes
    @masker_attributes ||= superclass.masker_attributes.dup
  end

  # Forwards calls to :mask_#{attribute} to the corresponding mask method
  # if attribute was configured with attr_masker
  #
  # Example
  #
  #   class User
  #     attr_masker :email, :key => 'my secret key'
  #   end
  #
  #   User.mask_email('SOME_masker_EMAIL_STRING')
  def method_missing(method, *arguments, &block)
    if method.to_s =~ /^mask_(.+)$/ && attr_masker?($1)
      send(:mask, $1, *arguments)
    else
      super
    end
  end

  class Masker

    # This default masker simply replaces any value with a fixed string.
    #
    # +opts+ is a Hash with the key :value that gives you the current attribute
    # value.
    #
    def self.mask opts
      '(redacted)'
    end
  end

  # Only include these methods in the rake task, and only run it in QA, cuz
  # they're DANGEROUS!
  module DangerousInstanceMethods

    # For each masker attribute, mask it, and save it!
    #
    def mask!
      return if self.class.masker_attributes.empty?

      updates = self.class.masker_attributes.reduce({}) do |acc, masker_attr|
        attr_name = masker_attr[0]
        column_name = masker_attr[1][:column_name] || attr_name
        masker_value = mask(attr_name)
        acc.merge!(column_name => masker_value)
      end

      self.class.all.update(id, updates)
    end
  end

  module InstanceMethods

    # masks a value for the attribute specified using options evaluated in the current object's scope
    #
    # Example
    #
    #  class User
    #    attr_accessor :secret_key
    #    attr_masker :email, :key => :secret_key
    #
    #    def initialize(secret_key)
    #      self.secret_key = secret_key
    #    end
    #  end
    #
    #  @user = User.new('some-secret-key')
    #  @user.mask(:email, 'test@example.com')
    def mask(attribute, value=nil)
      value = self.send(attribute) if value.nil?
      self.class.mask(attribute, value, evaluated_attr_masker_options_for(attribute))
    end

    protected

      # Returns attr_masker options evaluated in the current object's scope for the attribute specified
      # XXX:Keep
      def evaluated_attr_masker_options_for(attribute)
        self.class.masker_attributes[attribute.to_sym].inject({}) do |hash, (option, value)|
          hash.merge!(option => evaluate_attr_masker_option(value))
        end
      end

      # Evaluates symbol (method reference) or proc (responds to call) options
      # XXX:Keep
      #
      # If the option is not a symbol or proc then the original option is returned
      def evaluate_attr_masker_option(option)
        if option.is_a?(Symbol) && respond_to?(option)
          send(option)
        elsif option.respond_to?(:call)
          option.call(self)
        else
          option
        end
      end
  end
end

Object.extend AttrMasker
