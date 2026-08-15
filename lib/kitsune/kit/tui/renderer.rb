# frozen_string_literal: true

module Kitsune
  module Kit
    module Tui
      class Renderer
        MIN_WIDTH = 70
        MIN_HEIGHT = 18

        def render(state)
          width, height = state.terminal_size
          return small_terminal(width, height) if width < MIN_WIDTH || height < MIN_HEIGHT

          body = screen_lines(state, width, height - 4)
          lines = [top_border(state, width), *body, footer(state, width), bottom_border(width)]
          fit(lines, width, height)
        end

        private

        def screen_lines(state, width, height)
          return modal_lines(state, width, height) if state.modal

          case state.screen
          when :dashboard then dashboard(state, width, height)
          when :plan then plan(state, width, height)
          when :doctor then doctor(state, width, height)
          when :logs then logs(state, width, height)
          when :help then help_lines
          else [" Unknown screen "]
          end
        end

        def dashboard(state, width, height)
          left_width = [(width * 0.34).floor, 24].max
          resources = state.resources.empty? ? [{ name: "No managed resources", status: "pending" }] : state.resources
          left = resources.each_with_index.map do |resource, index|
            marker = index == state.selected_resource ? ">" : " "
            "#{marker} #{resource[:name].to_s.ljust(left_width - 13)} #{resource[:status]}"
          end
          right = ["Details", "", "Environment: #{state.environment}"]
          right.concat(state.operations.last([height - 6, 0].max).map { |operation| operation_line(operation) })
          columns(left, right, left_width, width, height)
        end

        def plan(state, width, _height)
          plan = state.result
          return [" Plan has not been built. Press p. "] unless plan

          [" Plan for #{plan.environment}", ""] + plan.changes.map do |change|
            marker = { "create" => "+", "update" => "~", "delete" => "-", "no_change" => "=" }.fetch(change.action)
            truncate(" #{marker} #{change.summary}", width - 2)
          end + ["", " #{plan.changed_count} change(s)"]
        end

        def doctor(state, width, _height)
          checks = state.result
          return [" Doctor has not run. Press d. "] unless checks

          checks.flat_map do |check|
            lines = [truncate(" #{check.status.upcase.ljust(5)} #{check.name}: #{check.message}", width - 2)]
            lines << truncate("       Fix: #{check.hint}", width - 2) if check.hint
            lines
          end
        end

        def logs(state, width, height)
          available = [height - 2, 0].max
          end_index = [state.logs.length - state.scroll_offset, 0].max
          start_index = [end_index - available, 0].max
          visible = state.logs[start_index...end_index] || []
          [" Logs", ""] + visible.map { |line| truncate(" #{line}", width - 2) }
        end

        def help_lines
          [
            " Keyboard shortcuts", "", " j/k or arrows  Select resource", " p              Build plan",
            " a              Apply the visible plan", " d              Run doctor", " r              Resume failed run",
            " l              Show logs", " Tab            Next screen", " PgUp/PgDn      Scroll logs",
            " ?              Toggle help", " q              Quit",
            " Ctrl+C         Cancel/quit"
          ]
        end

        def modal_lines(state, width, height)
          message = state.modal[:message]
          padding = [((height - 5) / 2), 0].max
          ([""] * padding) + [center("Confirmation", width - 2), "", center(message, width - 2),
                              center("Press y to confirm or n/Esc to cancel", width - 2)]
        end

        def columns(left, right, left_width, width, height)
          right_width = width - left_width - 4
          Array.new(height) do |index|
            " #{truncate(left[index].to_s, left_width).ljust(left_width)}│ #{truncate(right[index].to_s, right_width)}"
          end
        end

        def operation_line(operation)
          duration = operation[:duration_ms] ? " #{operation[:duration_ms]}ms" : ""
          progress = operation[:percent] ? " #{operation[:percent]}%" : ""
          "#{operation[:status].to_s.ljust(9)} #{operation[:summary]}#{progress}#{duration}"
        end

        def top_border(state, width)
          title = " Kitsune Kit · #{state.environment} · #{state.screen} "
          "┌#{title}#{'─' * [width - title.length - 2, 0].max}┐"
        end

        def footer(state, width)
          status = state.running ? "running" : (state.notification || "ready")
          content = truncate("├─ p plan  a apply  d doctor  r resume  l logs  ? help  q quit · #{status} ", width - 1)
          "#{content.ljust(width - 1, '─')}┤"
        end

        def bottom_border(width) = "└#{'─' * (width - 2)}┘"

        def small_terminal(width, height)
          fit(["Kitsune Kit", "", "Terminal too small (#{width}x#{height}).", "Minimum: #{MIN_WIDTH}x#{MIN_HEIGHT}.",
               "Resize or press q to quit."], width, height)
        end

        def fit(lines, width, height)
          lines.first(height).map { |line| truncate(line, width).ljust(width) }.then do |visible|
            (visible + Array.new([height - visible.length, 0].max, " " * width)).join("\n")
          end
        end

        def center(value, width) = value.to_s.center(width)
        def truncate(value, width) = value.length > width ? "#{value[0, [width - 1, 0].max]}…" : value
      end
    end
  end
end
