# frozen_string_literal: true

require "stringio"
require "spec_helper"

RSpec.describe "optional TUI" do
  let(:filter) { Kitsune::Kit::SecretFilter.new(["top-secret"]) }
  let(:store) do
    Kitsune::Kit::Tui::Store.new(environment: "production", secret_filter: filter, terminal_size: [90, 24])
  end
  let(:renderer) { Kitsune::Kit::Tui::Renderer.new }

  it "turns domain events into redacted, bounded view state" do
    205.times do |index|
      store.handle(Kitsune::Kit::Events::Event.build(
                     "operation_started",
                     run_id: "run",
                     resource: "step-#{index}",
                     summary: "Using top-secret at step #{index}"
                   ))
    end
    store.handle(Kitsune::Kit::Events::Event.build(
                   "operation_succeeded",
                   run_id: "run",
                   resource: "step-204",
                   summary: "Done",
                   duration_ms: 12
                 ))

    state = store.snapshot
    expect(state.logs.length).to eq(200)
    expect(state.logs.join).not_to include("top-secret")
    expect(state.operations.last).to include(resource: "step-204", status: "succeeded", duration_ms: 12)
  end

  it "keeps high-frequency log input bounded and responsive" do
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    10_000.times do |index|
      store.handle(Kitsune::Kit::Events::Event.build(
                     "warning_emitted", run_id: "load", message: "high-frequency line #{index}"
                   ))
    end
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    expect(store.snapshot.logs.length).to eq(Kitsune::Kit::Tui::Store::MAX_LOGS)
    expect(store.snapshot.logs.last).to end_with("high-frequency line 9999")
    expect(duration).to be < 10
  end

  it "renders deterministic dashboard, plan, doctor, logs, modal and small-terminal snapshots" do
    store.resources = [{ name: "server", status: "active" }, { name: "docker", status: "managed" }]
    dashboard = renderer.render(store.snapshot)
    expect(dashboard).to include("Kitsune Kit · production · dashboard", "> server", "p plan")

    plan = Kitsune::Kit::Plan.new(
      environment: "production",
      changes: [Kitsune::Kit::Change.new(resource: "docker", action: "create", summary: "Install Docker")]
    )
    store.show(:plan, result: plan)
    expect(renderer.render(store.snapshot)).to include("Plan for production", "+ Install Docker")

    check = Kitsune::Kit::Workflows::Check.new(name: "SSH", status: "warn", message: "Needs review", hint: "Fix it")
    store.show(:doctor, result: [check])
    expect(renderer.render(store.snapshot)).to include("WARN  SSH", "Fix: Fix it")

    store.show(:logs)
    expect(renderer.render(store.snapshot)).to include("Logs")
    store.modal(message: "Apply now?", action: :apply)
    expect(renderer.render(store.snapshot)).to include("Confirmation", "Apply now?")

    store.resize(40, 8)
    expect(renderer.render(store.snapshot)).to include("Terminal too small", "Minimum: 70x18")
  end

  it "supports keyboard navigation, confirmation, background work and quit" do
    actions = Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def apply
        @calls << :apply
        Kitsune::Kit::Result.success([])
      end
    end.new
    store.resources = [{ name: "server", status: "active" }, { name: "docker", status: "managed" }]
    controller = Kitsune::Kit::Tui::Controller.new(store: store, actions: actions)

    controller.handle("j")
    expect(store.snapshot.selected_resource).to eq(1)
    controller.handle("a")
    expect(store.snapshot.modal[:action]).to eq(:apply)
    controller.handle("y")
    controller.wait
    expect(actions.calls).to eq([:apply])
    controller.handle("q")
    expect(controller.exit_requested).to be(true)
  end

  it "routes plan and doctor shortcuts to their result screens" do
    actions = Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def plan
        @calls << :plan
        Kitsune::Kit::Result.success(:plan_result)
      end

      def doctor
        @calls << :doctor
        Kitsune::Kit::Result.success(:doctor_result)
      end
    end.new
    controller = Kitsune::Kit::Tui::Controller.new(store: store, actions: actions)

    controller.handle("p")
    controller.wait
    expect(store.snapshot).to have_attributes(screen: :plan, result: :plan_result)

    controller.handle("d")
    controller.wait
    expect(store.snapshot).to have_attributes(screen: :doctor, result: :doctor_result)
    expect(actions.calls).to eq(%i[plan doctor])
  end

  it "cycles screens with Tab and scrolls bounded logs with keys" do
    30.times do |index|
      store.handle(Kitsune::Kit::Events::Event.build(
                     "warning_emitted", run_id: "run", message: "line #{index}"
                   ))
    end
    controller = Kitsune::Kit::Tui::Controller.new(store: store, actions: Object.new)

    controller.handle("\t")
    expect(store.snapshot.screen).to eq(:plan)
    2.times { controller.handle("\t") }
    expect(store.snapshot.screen).to eq(:logs)
    newest = renderer.render(store.snapshot)
    expect(newest).to include("line 29")

    controller.handle(:page_up)
    older = renderer.render(store.snapshot)
    expect(store.snapshot.scroll_offset).to eq(5)
    expect(older).not_to include("warning_emitted: line 29")
    controller.handle(:page_down)
    expect(store.snapshot.scroll_offset).to eq(0)
  end

  it "requests cooperative cancellation with Ctrl+C while a worker is active" do
    started = Queue.new
    release = Queue.new
    actions = Class.new do
      attr_reader :cancelled

      define_method(:initialize) do |started_queue, release_queue|
        @started_queue = started_queue
        @release_queue = release_queue
      end

      def apply
        @started_queue << true
        @release_queue.pop
        Kitsune::Kit::Result.success([])
      end

      def cancel = @cancelled = true
    end.new(started, release)
    controller = Kitsune::Kit::Tui::Controller.new(store: store, actions: actions)
    controller.handle("a")
    controller.handle("y")
    started.pop

    controller.handle("\u0003")
    expect(actions.cancelled).to be(true)
    expect(store.snapshot.notification).to eq("Cancellation requested")
    release << true
    controller.wait
  end

  it "uses the same plan workflow and domain result as the conventional interface" do
    root = Dir.mktmpdir("kitsune-tui-parity")
    config = build_config
    provider = Kitsune::Kit::Adapters::FakeProvider.new
    state = Kitsune::Kit::StateStore.new(root: root)
    transport = Kitsune::Kit::Adapters::FakeTransport.new
    factory = Kitsune::Kit::Adapters::FakeTransportFactory.new(transport: transport)
    app = Kitsune::Kit::Application.new(
      config: config, provider: provider, state_store: state, transport_factory: factory
    )
    actions = Kitsune::Kit::Tui::Actions.new(application: app)

    tui_plan = actions.plan.value
    cli_plan = Kitsune::Kit::Workflows::BuildPlan.new(config: config, operations: app.operations).call.value

    expect(tui_plan.to_h).to eq(cli_plan.to_h)
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  it "renews cancellation so a later operation can succeed in the same TUI session" do
    root = Dir.mktmpdir("kitsune-tui-cancellation")
    config = build_config
    provider = Kitsune::Kit::Adapters::FakeProvider.new
    state = Kitsune::Kit::StateStore.new(root: root)
    transport = Kitsune::Kit::Adapters::FakeTransport.new
    factory = Kitsune::Kit::Adapters::FakeTransportFactory.new(transport: transport)
    app = Kitsune::Kit::Application.new(
      config: config, provider: provider, state_store: state, transport_factory: factory
    )
    actions = Kitsune::Kit::Tui::Actions.new(application: app)

    actions.cancel
    expect { actions.apply }.to raise_error(Kitsune::Kit::Cancellation::Cancelled)
    expect(actions.apply).to be_success
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  it "restores the terminal even when the application fails" do
    terminal = Class.new do
      attr_reader :restored

      def tty? = true

      def run
        yield self
      ensure
        @restored = true
      end

      def size = [90, 24]
      def draw(*) = nil
      def read_key(*) = raise("input failure")
    end.new
    actions = Object.new
    def actions.status
      Kitsune::Kit::Result.success(
        Kitsune::Kit::Workflows::EnvironmentStatus.new(
          environment: "production", server: nil, managed_resources: {}, last_operations: []
        )
      )
    end
    controller = Kitsune::Kit::Tui::Controller.new(store: store, actions: actions)
    application = Kitsune::Kit::Tui::Application.new(store: store, controller: controller, terminal: terminal)

    expect { application.call }.to raise_error("input failure")
    expect(terminal.restored).to be(true)
  end

  it "refuses to initialize full-screen mode without a TTY" do
    terminal = Kitsune::Kit::Tui::Terminal.new(input: StringIO.new, output: StringIO.new)

    expect { terminal.run { nil } }
      .to raise_error(Kitsune::Kit::Errors::ConfigurationError, /interactive terminal/)
  end

  it "draws rows at absolute positions without newline-driven scrolling" do
    output = StringIO.new
    terminal = Kitsune::Kit::Tui::Terminal.new(input: StringIO.new, output: output)

    terminal.draw("first row\nsecond row")

    expect(output.string).to eq("\e[1;1Hfirst row\e[2;1Hsecond row")
  end

  it "restores console mode even if alternate-screen entry fails after raw mode" do
    input = Class.new do
      attr_reader :restored_mode

      def tty? = true
      def console_mode = :original
      def raw! = @raw = true

      def console_mode=(value)
        @restored_mode = value
      end
    end.new
    output = Class.new do
      def tty? = true
      def write(*) = raise(IOError, "terminal write failed")
      def flush = nil
    end.new
    terminal = Kitsune::Kit::Tui::Terminal.new(input: input, output: output)

    expect { terminal.run { nil } }.to raise_error(IOError, /terminal write failed/)
    expect(input.restored_mode).to eq(:original)
  end
end
