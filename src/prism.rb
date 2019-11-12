module Prism
  @@instances = {}

  def self.instances
    @@instances
  end

  def self.mount(component)
    Mount.new(component)
  end

  class Mount
    def initialize(component)
      @component = component
    end

    def render
      JSON::stringify(@component.render)
    end

    def dispatch(messageJSON)
      message = JSON::parse(messageJSON)

      instance = Prism.instances[message["instance"]]

      if instance.respond_to? message["type"]
        instance.send(message["type"], *message["args"])
      else
        raise "Component #{instance.class} has no method ##{message["type"]}"
      end
    end

    def event(eventJSON, id)
      DOM.event(JSON::parse(eventJSON), id)
    end

    def http_response(responseJSON, id)
      HTTP._response(HTTP::Response.from_json(responseJSON), id)
    end
  end

  class Component

    def method_missing(method_name, *args, &block)
      options = {}
      className = ""
      children = []

      result = {}

      until args.empty?
        arg = args.shift

        case arg
        when String
          if arg.start_with?(".")
            className = arg
          else
            children = [text(arg)]
          end
        when Array
          children = arg
        when Object
          options = arg
        end
      end

      options.each do |key, value|
        next if value.is_a?(EventHandler) || (key.to_s).chars.first == '_'
        result[key] = value
      end

      result[:_type] = method_name
      result[:_class] = className
      options[:_children] = children || []

      result[:_children] = options[:_children].compact.map do |child|
        if child.is_a?(Prism::Component)
          child.render
        elsif child.is_a?(String)
          text(child)
        else
          child
        end
      end

      result[:on] ||= {}
      result[:on][:click] = options[:onClick].to_hash if options[:onClick]
      result[:on][:change] = options[:onChange].to_hash if options[:onChange]
      result[:on][:input] = options[:onInput].to_hash if options[:onInput]
      result[:on][:mousedown] = options[:onMousedown].to_hash if options[:onMousedown]
      result[:on][:mouseup] = options[:onMouseup].to_hash if options[:onMouseup]
      result[:on][:keydown] = options[:onKeydown].to_hash if options[:onKeydown]
      result[:on][:keyup] = options[:onKeyup].to_hash if options[:onKeyup]
      result[:on][:scroll] = options[:onScroll].to_hash if options[:onScroll]

      if options[:on]
        event_handlers = {}

        options[:on].each do |key, value|
          event_handlers[key] = value.to_hash
        end

        result[:on] = event_handlers
      end

      result
    end

    def text(t)
      {:type => "text", :content => t.to_s}
    end

    def call(method_name, *args)
      Prism.instances[object_id] = self # TODO - this is a memory leak
      EventHandler.new(object_id, method_name).with(*args)
    end

    def stop_propagation
      Prism.instances[object_id] = self # TODO - this is a memory leak
      EventHandler.new(object_id, nil).stop_propagation
    end

    def prevent_default
      Prism.instances[object_id] = self # TODO - this is a memory leak
      EventHandler.new(object_id, nil).prevent_default
    end

    def render
      raise "Unimplemented render method for #{self.class.name}"
    end
  end

  class EventHandler
    attr_reader :method_name

    def initialize(id, method_name, args = [], options = {})
      @id = id
      @method_name = method_name
      @args = args
      @options = {prevent_default: false, stop_propagation: false}.merge(options)
    end

    def with(*additionalArgs)
      new_args = additionalArgs.map { |a| {type: :constant, value: a} }

      EventHandler.new(@id, method_name, @args + new_args, @options)
    end

    def with_event
      EventHandler.new(@id, method_name, @args + [{type: :event}], @options)
    end

    def with_event_data(*property_names)
      new_args = property_names.map { |item| {type: :event_data, key: item } }

      EventHandler.new(@id, method_name, @args + new_args, @options)
    end

    def with_target_data(*items)
      target_args = items.map { |item| {type: :target_data, key: item } }
      EventHandler.new(@id, method_name, @args + target_args, @options)
    end

    def prevent_default
      EventHandler.new(@id, method_name, @args, @options.merge(prevent_default: true))
    end

    def stop_propagation
      EventHandler.new(@id, method_name, @args, @options.merge(stop_propagation: true))
    end

    def to_hash
      {
        instance: @id,
        type: @method_name,
        args: @args,
        prevent_default: @options[:prevent_default],
        stop_propagation: @options[:stop_propagation]
      }
    end
  end
end

module DOM
  @@event_id = 0
  @@listeners = {}

  def self.get_event_id
    @@event_id += 1

    @@event_id.to_s
  end

  def self.add_listener(id, &block)
    @@listeners[id] = block
  end

  def self.select(selector)
    ElementSelection.new(selector)
  end

  def self.event(eventData, id)
    @@listeners[id].call(eventData)
  end

  class ElementSelection
    def initialize(selector)
      @selector = selector
    end

    def on(eventName, &block)
      id = DOM.get_event_id
      InternalDOM.add_event_listener(@selector, eventName, id)
      DOM.add_listener(id, &block)
    end
  end
end

module HTTP
  @@event_id = 0
  @@listeners = {}

  def self.get_event_id
    @@event_id += 1

    @@event_id.to_s
  end

  def self.add_listener(id, &block)
    @@listeners[id] = block
  end

  def self.get(url, &block)
    id = HTTP.get_event_id

    InternalHTTP.http_request(url, id)

    HTTP.add_listener(id, &block)
  end

  def self._response(text, id)
    @@listeners[id].call(text)
  end

  class Response < Struct.new(:body)
    def self.from_json(json)
      data = JSON::parse(json)

      new(data["body"])
    end
  end
end
