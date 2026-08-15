# frozen_string_literal: true

require "io/console"
require "io/wait"

module Kitsune
  module Kit
    module Tui
      class Terminal
        ALT_SCREEN = "\e[?1049h"
        MAIN_SCREEN = "\e[?1049l"
        DISABLE_WRAP = "\e[?7l"
        ENABLE_WRAP = "\e[?7h"

        def initialize(input: $stdin, output: $stdout)
          @input = input
          @output = output
        end

        def tty? = input.tty? && output.tty?

        def run
          raise Errors::ConfigurationError, "the TUI requires an interactive terminal" unless tty?

          enter
          yield self
        ensure
          restore
        end

        def size
          rows, columns = output.winsize
          [columns, rows]
        rescue SystemCallError, NoMethodError
          [100, 30]
        end

        def draw(content)
          frame = content.lines(chomp: true).each_with_index.map do |line, index|
            "\e[#{index + 1};1H#{line}"
          end.join
          output.write(frame)
          output.flush
        end

        def read_key(timeout: 0.1)
          return unless input.wait_readable(timeout)

          first = input.read_nonblock(1)
          return first unless first == "\e"

          sequence = first.dup
          sequence << input.read_nonblock(1) while sequence.length < 6 && input.wait_readable(0.005)
          { "\e[A" => :up, "\e[B" => :down, "\e[5~" => :page_up, "\e[6~" => :page_down }
            .fetch(sequence, :escape)
        rescue IO::WaitReadable
          nil
        end

        private

        attr_reader :input, :output

        def enter
          @original_console_mode = input.console_mode
          input.raw!
          @active = true
          output.write("#{ALT_SCREEN}#{DISABLE_WRAP}\e[?25l\e[2J\e[H")
          output.flush
        end

        def restore
          return unless @active

          restore_console
          restore_screen
          @active = false
        end

        def restore_console
          input.console_mode = @original_console_mode if @original_console_mode
        rescue SystemCallError, IOError
          nil
        end

        def restore_screen
          output.write("#{ENABLE_WRAP}\e[?25h#{MAIN_SCREEN}")
          output.flush
        rescue SystemCallError, IOError
          nil
        end
      end
    end
  end
end
