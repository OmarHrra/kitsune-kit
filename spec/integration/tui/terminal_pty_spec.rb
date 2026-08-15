# frozen_string_literal: true

require "pty"
require "rbconfig"
require "timeout"
require "English"
require "spec_helper"

RSpec.describe "TUI terminal lifecycle in a pseudo-terminal", :integration do
  let(:library_path) { File.expand_path("../../../lib", __dir__) }
  let(:restore_sequence) do
    "#{Kitsune::Kit::Tui::Terminal::ENABLE_WRAP}\e[?25h#{Kitsune::Kit::Tui::Terminal::MAIN_SCREEN}"
  end

  it "enters and restores the terminal on a normal exit" do
    output, status = run_in_pty(<<~RUBY)
      require "kitsune/kit"
      Kitsune::Kit::Tui::Terminal.new.run do
        STDOUT.write("READY")
        STDOUT.flush
      end
    RUBY

    expect(status).to be_success
    expect(output).to include(Kitsune::Kit::Tui::Terminal::ALT_SCREEN,
                              Kitsune::Kit::Tui::Terminal::DISABLE_WRAP, "READY")
    expect(output).to end_with(restore_sequence)
  end

  it "restores the terminal when the process receives SIGINT" do
    output, status = run_in_pty(<<~RUBY, interrupt_after: "READY")
      require "kitsune/kit"
      Kitsune::Kit::Tui::Terminal.new.run do
        STDOUT.write("READY")
        STDOUT.flush
        sleep 30
      end
    RUBY

    expect(status).not_to be_success
    expect(output).to include("READY", restore_sequence)
  end

  def run_in_pty(program, interrupt_after: nil)
    output = +""
    status = nil
    PTY.spawn(RbConfig.ruby, "-I#{library_path}", "-e", program) do |reader, _writer, pid|
      wait_for_output(reader, output, interrupt_after) if interrupt_after
      Process.kill("INT", pid) if interrupt_after
      read_to_end(reader, output)
      _, status = Process.wait2(pid)
    rescue Errno::ECHILD
      status ||= $CHILD_STATUS
    end
    [output, status]
  end

  def wait_for_output(reader, output, marker)
    Timeout.timeout(5) do
      output << reader.readpartial(1024) until output.include?(marker)
    end
  end

  def read_to_end(reader, output)
    Timeout.timeout(5) { loop { output << reader.readpartial(1024) } }
  rescue EOFError, Errno::EIO
    nil
  end
end
