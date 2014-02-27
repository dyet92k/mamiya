require 'mamiya/util/label_matcher'
require 'thread'

module Mamiya
  class DSL
    class TaskNotDefinedError < Exception; end
    class HelperNotFound < Exception; end

    def initialize
      @variables = {}
      @tasks = {}
      @hooks = {}
      @eval_lock = Mutex.new
      @use_lock = Mutex.new
    end

    def self.defaults
      @defaults ||= {}
    end

    def self.define_variable_accessor(name)
      k = name.to_sym
      return if self.instance_methods.include?(k)

      define_method(k) { @variables[k] || self.class.defaults[k] }
    end

    def self.set_default(key, value)
      k = key.to_sym
      defaults[k] = value
      self.define_variable_accessor(k)
    end

    def self.add_hook(name)
      define_method(name) do |*args, &block|
        @hooks[name] ||= []

        if block
          options = args.pop if args.last.kind_of?(Hash)
          case args.first
          when :overwrite
            @hooks[name] = [[block, options]]
          when :prepend
            @hooks[name][0,0] = [[block, options]]
          else
            @hooks[name] << [block, options]
          end
        else
          matcher = Mamiya::Util::LabelMatcher::Simple.new(args)
          Proc.new { |*args|
            @hooks[name].each do |(hook, options)|
              options ||= {}
              next if options[:only] && !matcher.match?(*options[:only])
              next if options[:except] && matcher.match?(*options[:except])
              hook.call *args
            end
          }
        end
      end
    end

    def evaluate!(str = nil, filename = nil, lineno = nil, &block)
      @eval_lock.synchronize {
        begin
          if block_given?
            self.instance_eval(&block)
          elsif str
            @file = filename if filename

            if str && filename && lineno
              self.instance_eval(str, filename, lineno)
            elsif str && filename
              self.instance_eval(str, filename)
            elsif str
              self.instance_eval(str)
            end
          end
        ensure
          @file = nil
        end
      }
    end

    def load!(file)
      evaluate! File.read(file), file, 1
    end

    def use(name, options={})
      helper_file = find_helper_file(name)
      raise HelperNotFound unless helper_file

      @use_lock.lock unless @use_lock.owned? # to avoid lock recursively

      @_options = options
      self.instance_eval File.read(helper_file).prepend("options = @_options; @_options = nil;\n"), helper_file, 1

    ensure
      @_options = nil
      @use_lock.unlock if @use_lock.owned?
    end

    def set(key, value)
      k = key.to_sym
      self.class.define_variable_accessor(key) unless self.methods.include?(k)
      @variables[k] = value
    end

    def set_default(key, value)
      k = key.to_sym
      return @variables[k] if @variables.key?(k)
      set(k, value)
    end

    def task(name, &block)
      @tasks[name] = block
    end

    def invoke(name)
      raise TaskNotDefinedError unless @tasks[name]
      self.instance_eval &@tasks[name]
    end

    def load_path
      (@variables[:load_path] ||= []) +
        [
          "#{__dir__}/helpers",
          *(@file ? ["#{File.dirname(@file)}/helpers"] : [])
        ]
    end

    private

    def find_helper_file(name)
      load_path.find do |_| # Using find to return nil when not found
        path = File.join(_, "#{name}.rb")
        break path if File.exists?(path)
      end
    end

    # TODO: hook call context methods
    #https://gist.github.com/sorah/9263951
  end
end
