# frozen_string_literal: true

require "stringio"

RSpec.describe "Mini CI plugins" do
  around do |example|
    MiniCi::Plugin.reset!
    example.run
  ensure
    MiniCi::Plugin.reset!
  end

  it "registers valid plugin metadata and freezes returned collections" do
    plugin = MiniCi::Plugin.register(name: "demo-plugin", version: "1.0.0", description: "Demo")

    expect(plugin.name).to eq("demo-plugin")
    expect(plugin.version).to eq("1.0.0")
    expect(MiniCi::Plugin.registry.plugins).to contain_exactly(plugin)
    expect { MiniCi::Plugin.registry.plugins << plugin }.to raise_error(FrozenError)
  end

  it "rejects invalid plugin names and missing versions" do
    expect { MiniCi::Plugin.register(name: "Bad Plugin", version: "1.0.0") }
      .to raise_error(MiniCi::PluginRegistrationError, /plugin name must match/)

    expect { MiniCi::Plugin.register(name: "good-plugin", version: " ") }
      .to raise_error(MiniCi::PluginRegistrationError, /version must be a non-empty string/)
  end

  it "rejects duplicate plugins" do
    MiniCi::Plugin.register(name: "demo-plugin", version: "1.0.0")

    expect { MiniCi::Plugin.register(name: "demo-plugin", version: "1.0.1") }
      .to raise_error(MiniCi::PluginRegistrationError, /already registered/)
  end

  it "rejects incompatible plugin API versions" do
    expect { MiniCi::Plugin.register(name: "future-plugin", version: "2.0.0", api_version: "2") }
      .to raise_error(MiniCi::PluginRegistrationError, /requires API version 2/)
  end

  it "stores callbacks in plugin and declaration order" do
    events = []
    MiniCi::Plugin.register(name: "first-plugin", version: "1.0.0") do |plugin|
      plugin.before_item { events << "first-a" }
      plugin.before_item { events << "first-b" }
    end
    MiniCi::Plugin.register(name: "second-plugin", version: "1.0.0") do |plugin|
      plugin.before_item { events << "second" }
    end

    runner = MiniCi::Plugin::Runner.new(registry: MiniCi::Plugin.registry)
    runner.invoke(:before_item, MiniCi::Plugin::Context.new)

    expect(events).to eq(%w[first-a first-b second])
  end

  it "returns structured plugin failures and stops later callbacks for the event" do
    events = []
    MiniCi::Plugin.register(name: "broken-plugin", version: "1.0.0") do |plugin|
      plugin.after_run { raise "boom" }
    end
    MiniCi::Plugin.register(name: "later-plugin", version: "1.0.0") do |plugin|
      plugin.after_run { events << "later" }
    end

    failure = MiniCi::Plugin::Runner.new(registry: MiniCi::Plugin.registry)
                                    .invoke(:after_run, MiniCi::Plugin::Context.new)

    expect(failure.plugin_name).to eq("broken-plugin")
    expect(failure.event).to eq(:after_run)
    expect(events).to be_empty
  end

  it "loads explicit plugin files only once by canonical path" do
    directory = Dir.mktmpdir
    plugin_file = File.join(directory, "demo.rb")
    File.write(plugin_file, <<~RUBY)
      MiniCi::Plugin.register(name: "loaded-plugin", version: "1.0.0")
    RUBY

    loader = MiniCi::Plugin::Loader.new(registry: MiniCi::Plugin.registry, workspace: directory)
    loader.load(default: false, files: [plugin_file, plugin_file])

    expect(MiniCi::Plugin.registry.plugins.map(&:name)).to eq(["loaded-plugin"])
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  it "loads plugin directories alphabetically" do
    directory = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(directory, "plugins"))
    File.write(File.join(directory, "plugins", "b.rb"), 'MiniCi::Plugin.register(name: "b-plugin", version: "1.0.0")')
    File.write(File.join(directory, "plugins", "a.rb"), 'MiniCi::Plugin.register(name: "a-plugin", version: "1.0.0")')

    loader = MiniCi::Plugin::Loader.new(registry: MiniCi::Plugin.registry, workspace: directory)
    loader.load(default: false, directories: [File.join(directory, "plugins")])

    expect(MiniCi::Plugin.registry.plugins.map(&:name)).to eq(%w[a-plugin b-plugin])
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  it "reports plugin load errors with the source path" do
    directory = Dir.mktmpdir
    plugin_file = File.join(directory, "broken.rb")
    File.write(plugin_file, "raise 'load failure'")

    loader = MiniCi::Plugin::Loader.new(registry: MiniCi::Plugin.registry, workspace: directory)

    expect { loader.load(default: false, files: [plugin_file]) }
      .to raise_error(MiniCi::PluginLoadError, /Failed to load plugin .*broken\.rb/)
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  it "executes custom plugin item types in the pipeline" do
    output = StringIO.new
    MiniCi::Plugin.register(name: "message-plugin", version: "1.0.0") do |plugin|
      plugin.register_item_type("message") do |input, context|
        context.output.puts input.fetch("text")
        MiniCi::Plugin::ItemResult.new(
          success: true,
          plugin_name: "message-plugin",
          item_type: "message",
          metadata: { "message_length" => input.fetch("text").length }
        )
      end
    end
    step = MiniCi::Step.new(name: "Message", uses: "message", with: { "text" => "hello" })

    result = MiniCi::Pipeline.new(
      name: "Plugin Pipeline",
      steps: [step],
      reporter: MiniCi::Reporter.new(output: output),
      plugin_registry: MiniCi::Plugin.registry
    ).run

    expect(result).to be_success
    expect(output.string).to include("hello")
    expect(result.step_results.first.plugin_item_result.metadata).to eq("message_length" => 5)
  end

  it "runs plugin configuration validators after core parsing" do
    MiniCi::Plugin.register(name: "policy-plugin", version: "1.0.0") do |plugin|
      plugin.validate_configuration { |_configuration| ["policy failed"] }
    end
    directory = Dir.mktmpdir
    config = File.join(directory, "pipeline.yml")
    File.write(config, <<~YAML)
      name: Validator Example
      steps:
        - name: Step
          run: echo hi
    YAML

    expect { MiniCi::ConfigLoader.new(path: config, plugin_registry: MiniCi::Plugin.registry).load }
      .to raise_error(MiniCi::ConfigurationError, /Plugin validation failed \[policy-plugin\]: policy failed/)
  ensure
    FileUtils.remove_entry(directory) if directory
  end
end
