module Trailblazer
  # Running a Circuit instance will run all tasks sequentially depending on the former's result.
  # Each task is called and retrieves the former task's return values.
  #
  # Note: Please use #Activity as a public circuit builder.
  #
  # @param map         [Hash] Defines the wiring.
  # @param stop_events [Array] Tasks that stop execution of the circuit.
  # @param name        [Hash] Names for tracing, debugging and exceptions. `:id` is a reserved key for circuit name.
  #
  #   result = circuit.(start_at, *args)
  #
  # @see Activity
  # @api semi-private
  class Circuit
    def initialize(map, stop_events, name)
      @map         = map
      @stop_events = stop_events
      @name        = name
    end

    Run = ->(activity, direction, *args) { activity.(direction, *args) }

    # Runs the circuit. Stops when hitting a End event or subclass thereof.
    # This method throws exceptions when the return value of a task doesn't match
    # any wiring.
    #
    # @param activity A task from the circuit where to start
    # @param args An array of options passed to the first task.
    def call(activity, options, flow_options={}, *args)
      direction = nil
      runner    = flow_options[:runner] || Run

      loop do
        direction, options, flow_options, *args = runner.( activity, direction, options, flow_options, *args )

        # Stop execution of the circuit when we hit a stop event (< End). This could be an activity's End or Suspend.
        return [ direction, options, flow_options, *args ] if @stop_events.include?(activity)

        activity = next_for(activity, direction) do |next_activity, in_map|
          activity_name = @name[activity] || activity # TODO: this must be implemented only once, somewhere.
          raise IllegalInputError.new("#{@name[:id]} #{activity_name}") unless in_map
          raise IllegalOutputSignalError.new("from #{@name[:id]}: `#{activity_name}`===>[ #{direction.inspect} ]") unless next_activity
        end
      end
    end

    # Returns the circuit's components.
    def to_fields
      [ @map, @stop_events, @name]
    end

  private
    def next_for(last_activity, emitted_direction)
      # p @map
      in_map        = false
      cfg           = @map.keys.find { |t| t == last_activity } and in_map = true
      cfg = @map[cfg] if cfg
      cfg         ||= {}
      next_activity = cfg[emitted_direction]
      yield next_activity, in_map

      next_activity
    end

    class IllegalInputError < RuntimeError
    end

    class IllegalOutputSignalError < RuntimeError
    end

    # End event is just another callable task.
    # Any instance of subclass of End will halt the circuit's execution when hit.
    class End
      def initialize(name, options={})
        @name    = name
        @options = options
      end

      def call(direction, *args)
        [ self, *args ]
      end
    end

    class Start < End
      def call(direction, *args)
        [ Right, *args ]
      end
    end

    # Builder for Circuit::End when defining the Activity's circuit.
    def self.End(name, options={})
      End.new(name, options)
    end

    class Signal;         end
		class Right < Signal; end
    class Left  < Signal; end
  end
end
