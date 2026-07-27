# frozen_string_literal: true

require "tempfile"
require "tmpdir"

RSpec.describe MiniCi::ConfigLoader do
  def write_config(content, directory: Dir.mktmpdir)
    path = File.join(directory, "pipeline.yml")
    File.write(path, content)
    [path, directory]
  end

  def loader_for(path)
    described_class.new(path: path)
  end

  describe "#load" do
    it "loads a valid configuration" do
      path, directory = write_config(<<~YAML)
        name: Example Pipeline
        steps:
          - name: First step
            run: echo first
          - name: Second step
            run: echo second
      YAML

      config = loader_for(path).load

      expect(config.steps.length).to eq(2)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "returns the pipeline name" do
      path, directory = write_config(<<~YAML)
        name: My Pipeline
        steps:
          - name: Step
            run: echo hi
      YAML

      config = loader_for(path).load

      expect(config.name).to eq("My Pipeline")
      expect(config.name_explicit).to be(true)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "creates steps in the correct order" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Alpha
            run: echo alpha
          - name: Beta
            run: echo beta
      YAML

      config = loader_for(path).load

      expect(config.steps.map(&:name)).to eq(["Alpha", "Beta"])
      expect(config.steps.map(&:command)).to eq(["echo alpha", "echo beta"])
    ensure
      FileUtils.remove_entry(directory)
    end

    it "uses a sensible default pipeline name when name is omitted" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
      YAML

      config = loader_for(path).load

      expect(config.name).to eq("Mini CI")
      expect(config.name_explicit).to be(false)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "uses an empty global environment when env is omitted" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
      YAML

      config = loader_for(path).load

      expect(config.env).to eq({})
    ensure
      FileUtils.remove_entry(directory)
    end

    it "loads valid global environment variables" do
      path, directory = write_config(<<~YAML)
        env:
          APP_ENV: test
          FEATURE_FLAG_2: enabled
        steps:
          - name: Step
            run: echo hi
      YAML

      config = loader_for(path).load

      expect(config.env).to eq(
        "APP_ENV" => "test",
        "FEATURE_FLAG_2" => "enabled"
      )
    ensure
      FileUtils.remove_entry(directory)
    end

    it "converts scalar environment values to strings" do
      path, directory = write_config(<<~YAML)
        env:
          PORT: 3000
          DEBUG: false
          EMPTY_VALUE: ""
        steps:
          - name: Step
            run: echo hi
      YAML

      config = loader_for(path).load

      expect(config.env).to eq(
        "PORT" => "3000",
        "DEBUG" => "false",
        "EMPTY_VALUE" => ""
      )
    ensure
      FileUtils.remove_entry(directory)
    end

    it "uses an empty step environment when env is omitted" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
      YAML

      config = loader_for(path).load

      expect(config.steps.first.env).to eq({})
    ensure
      FileUtils.remove_entry(directory)
    end

    it "loads valid step environment variables" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            env:
              APP_ENV: integration
              FEATURE_FLAG: enabled
      YAML

      config = loader_for(path).load

      expect(config.steps.first.env).to eq(
        "APP_ENV" => "integration",
        "FEATURE_FLAG" => "enabled"
      )
    ensure
      FileUtils.remove_entry(directory)
    end

    it "uses nil when step timeout is omitted" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
      YAML

      config = loader_for(path).load

      expect(config.steps.first.timeout).to be_nil
    ensure
      FileUtils.remove_entry(directory)
    end

    it "accepts an integer timeout" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            timeout: 10
      YAML

      config = loader_for(path).load

      expect(config.steps.first.timeout).to eq(10)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "accepts a floating-point timeout" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            timeout: 2.5
      YAML

      config = loader_for(path).load

      expect(config.steps.first.timeout).to eq(2.5)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "defaults retries to zero" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
      YAML

      config = loader_for(path).load

      expect(config.steps.first.retries).to eq(0)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "defaults retry delay to zero" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
      YAML

      config = loader_for(path).load

      expect(config.steps.first.retry_delay).to eq(0)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "loads valid retry values" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retries: 2
            retry_delay: 1.5
      YAML

      config = loader_for(path).load

      expect(config.steps.first.retries).to eq(2)
      expect(config.steps.first.retry_delay).to eq(1.5)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "accepts integer retries" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retries: 3
      YAML

      config = loader_for(path).load

      expect(config.steps.first.retries).to eq(3)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "accepts integer and decimal retry delays" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Integer delay
            run: echo hi
            retry_delay: 1
          - name: Decimal delay
            run: echo hi
            retry_delay: 0.5
      YAML

      config = loader_for(path).load

      expect(config.steps.map(&:retry_delay)).to eq([1, 0.5])
    ensure
      FileUtils.remove_entry(directory)
    end

    it "uses empty hook arrays when hooks are omitted" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
      YAML

      config = loader_for(path).load

      expect(config.before_all).to eq([])
      expect(config.after_all).to eq([])
    ensure
      FileUtils.remove_entry(directory)
    end

    it "loads valid hooks in order" do
      path, directory = write_config(<<~YAML)
        before_all:
          - name: Prepare
            run: echo prepare
          - name: Warm cache
            run: echo cache
        steps:
          - name: Step
            run: echo step
        after_all:
          - name: Cleanup
            run: echo cleanup
      YAML

      config = loader_for(path).load

      expect(config.before_all.map(&:name)).to eq(["Prepare", "Warm cache"])
      expect(config.before_all.map(&:command)).to eq(["echo prepare", "echo cache"])
      expect(config.after_all.map(&:name)).to eq(["Cleanup"])
    ensure
      FileUtils.remove_entry(directory)
    end

    it "preserves hook options" do
      path, directory = write_config(<<~YAML)
        before_all:
          - name: Prepare
            run: echo prepare
            timeout: 2
            retries: 1
            retry_delay: 0.5
            env:
              HOOK_ENV: "yes"
        steps:
          - name: Step
            run: echo step
      YAML

      hook = loader_for(path).load.before_all.first

      expect(hook.timeout).to eq(2)
      expect(hook.retries).to eq(1)
      expect(hook.retry_delay).to eq(0.5)
      expect(hook.env).to eq("HOOK_ENV" => "yes")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects hook containers that are not arrays" do
      path, directory = write_config(<<~YAML)
        before_all:
          name: Prepare
          run: echo prepare
        steps:
          - name: Step
            run: echo step
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: before_all must be an array")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects invalid hook entries and identifies the phase and index" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo step
        after_all:
          - name: Cleanup one
            run: echo cleanup
          - name: Cleanup two
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: after_all hook 2 is missing "run"')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects invalid hook options and identifies the hook" do
      path, directory = write_config(<<~YAML)
        before_all:
          - name: Prepare
            run: echo prepare
            retries: -1
        steps:
          - name: Step
            run: echo step
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: before_all hook 1 retries must be a non-negative integer")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects invalid hook environment variables" do
      path, directory = write_config(<<~YAML)
        before_all:
          - name: Prepare
            run: echo prepare
            env:
              BAD-NAME: value
        steps:
          - name: Step
            run: echo step
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, /before_all hook 1 env/)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects invalid hook timeouts" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo step
        after_all:
          - name: Cleanup
            run: echo cleanup
            timeout: 0
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: after_all hook 1 timeout must be greater than 0")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects invalid hook retry delays" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo step
        after_all:
          - name: Cleanup
            run: echo cleanup
            retry_delay: -0.1
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: after_all hook 1 retry_delay must be a non-negative number")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "defaults normal steps to run on success" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo step
      YAML

      expect(loader_for(path).load.steps.first.when_policy).to eq(:success)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "defaults before_all hooks to run on success" do
      path, directory = write_config(<<~YAML)
        before_all:
          - name: Prepare
            run: echo prepare
        steps:
          - name: Step
            run: echo step
      YAML

      expect(loader_for(path).load.before_all.first.when_policy).to eq(:success)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "defaults after_all hooks to always run" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo step
        after_all:
          - name: Cleanup
            run: echo cleanup
      YAML

      expect(loader_for(path).load.after_all.first.when_policy).to eq(:always)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "loads valid when policies" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Failure step
            run: echo failure
            when: failure
          - name: Always step
            run: echo always
            when: always
          - name: Never step
            run: echo never
            when: never
      YAML

      expect(loader_for(path).load.steps.map(&:when_policy)).to eq([:failure, :always, :never])
    ensure
      FileUtils.remove_entry(directory)
    end

    it "marks explicit when policies" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Explicit
            run: echo explicit
            when: success
      YAML

      expect(loader_for(path).load.steps.first).to be_when_policy_explicit
    ensure
      FileUtils.remove_entry(directory)
    end

    it "parses valid if expressions" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Conditional
            run: echo conditional
            if: env.DEPLOY == "true"
      YAML

      condition = loader_for(path).load.steps.first.condition

      expect(condition.variable_name).to eq("DEPLOY")
      expect(condition.operator).to eq("==")
      expect(condition.expected_value).to eq("true")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects invalid when policies with phase and index" do
      path, directory = write_config(<<~YAML)
        before_all:
          - name: Prepare
            run: echo prepare
            when: sometimes
        steps:
          - name: Step
            run: echo step
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: before_all hook 1 has invalid when value "sometimes"')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects non-string when policies" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo step
        after_all:
          - name: Cleanup
            run: echo cleanup
            when: true
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: after_all hook 1 when must be a string")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects empty if expressions" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Conditional
            run: echo conditional
            if: ""
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 if expression is empty")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects malformed if expressions" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Conditional
            run: echo conditional
            if: env.DEPLOY
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, /Invalid pipeline configuration: step 1 has unsupported if expression/)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects invalid if variable names" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Conditional
            run: echo conditional
            if: env.BAD-NAME == "true"
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, /Invalid pipeline configuration: step 1 has unsupported if expression/)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects invalid if operators" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Conditional
            run: echo conditional
            if: env.DEPLOY = "true"
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, /Supported format/)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects unsupported logical if expressions" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Conditional
            run: echo conditional
            if: env.A == "x" && env.B == "y"
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, /Supported format/)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "uses nil matrix when matrix is omitted" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo step
      YAML

      expect(loader_for(path).load.matrix).to be_nil
    ensure
      FileUtils.remove_entry(directory)
    end

    it "loads a valid matrix and preserves order" do
      path, directory = write_config(<<~YAML)
        matrix:
          ruby:
            - "3.2"
            - "3.3"
          database:
            - sqlite
            - postgres
        steps:
          - name: Step
            run: echo step
      YAML

      matrix = loader_for(path).load.matrix

      expect(matrix.dimensions.keys).to eq(["ruby", "database"])
      expect(matrix.dimensions["ruby"]).to eq(["3.2", "3.3"])
      expect(matrix.dimensions["database"]).to eq(["sqlite", "postgres"])
    ensure
      FileUtils.remove_entry(directory)
    end

    it "converts scalar matrix values to strings" do
      path, directory = write_config(<<~YAML)
        matrix:
          debug:
            - true
            - false
          shard:
            - 1
            - 2
        steps:
          - name: Step
            run: echo step
      YAML

      matrix = loader_for(path).load.matrix

      expect(matrix.dimensions["debug"]).to eq(["true", "false"])
      expect(matrix.dimensions["shard"]).to eq(["1", "2"])
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects an empty matrix" do
      path, directory = write_config(<<~YAML)
        matrix: {}
        steps:
          - name: Step
            run: echo step
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: matrix must not be empty")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects a matrix that is not a mapping" do
      path, directory = write_config(<<~YAML)
        matrix:
          - ruby
        steps:
          - name: Step
            run: echo step
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: matrix must be a mapping")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects invalid matrix keys" do
      path, directory = write_config(<<~YAML)
        matrix:
          ruby-version:
            - "3.3"
        steps:
          - name: Step
            run: echo step
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: matrix key "ruby-version" is invalid')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects duplicate matrix keys" do
      path, directory = write_config(<<~YAML)
        matrix:
          ruby:
            - "3.2"
          ruby:
            - "3.3"
        steps:
          - name: Step
            run: echo step
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: duplicate key "ruby"')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects empty matrix value arrays" do
      path, directory = write_config(<<~YAML)
        matrix:
          ruby: []
        steps:
          - name: Step
            run: echo step
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: matrix value list for "ruby" must not be empty')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects non-array matrix value lists" do
      path, directory = write_config(<<~YAML)
        matrix:
          ruby: "3.3"
        steps:
          - name: Step
            run: echo step
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: matrix value list for "ruby" must be an array')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects null, nested array, and mapping matrix values" do
      [
        "ruby:\n  -",
        "ruby:\n  - [nested]",
        "ruby:\n  - version: \"3.3\""
      ].each do |matrix_yaml|
        path, directory = write_config(<<~YAML)
          matrix:
            #{matrix_yaml.gsub("\n", "\n  ")}
          steps:
            - name: Step
              run: echo step
        YAML

        expect { loader_for(path).load }
          .to raise_error(MiniCi::ConfigurationError, /matrix value 1 for "ruby" must be a scalar/)
        FileUtils.remove_entry(directory)
      end
    end

    it "rejects matrices over the expansion limit before execution" do
      values = (1..257).map { |number| "            - #{number}" }.join("\n")
      path, directory = write_config(<<~YAML)
        matrix:
          shard:
#{values}
        steps:
          - name: Step
            run: echo step
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, /exceeding the limit of 256/)
    ensure
      FileUtils.remove_entry(directory) if directory && File.exist?(directory)
    end

    it "raises when the configuration file is missing" do
      directory = Dir.mktmpdir

      Dir.chdir(directory) do
        expect { loader_for("missing.yml").load }
          .to raise_error(MiniCi::FileNotFoundError, "missing.yml was not found")
      end
    ensure
      FileUtils.remove_entry(directory)
    end

    it "raises when the YAML is malformed" do
      path, directory = write_config("name: [\nsteps:\n  - name: bad\n")

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, /Invalid YAML/)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "raises when steps are missing" do
      path, directory = write_config(<<~YAML)
        name: No Steps
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: missing "steps"')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects global env that is not a mapping" do
      path, directory = write_config(<<~YAML)
        env: test
        steps:
          - name: Step
            run: echo hi
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: global env must be a mapping")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects step env that is not a mapping" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            env: test
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 env must be a mapping")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "raises when steps is not an array" do
      path, directory = write_config(<<~YAML)
        steps: echo hello
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: "steps" must be an array')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "raises when steps is empty" do
      path, directory = write_config(<<~YAML)
        steps: []
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: "steps" must not be empty')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "raises when a step is not a mapping" do
      path, directory = write_config(<<~YAML)
        steps:
          - echo hello
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 must be a mapping")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "raises when a step is missing name" do
      path, directory = write_config(<<~YAML)
        steps:
          - run: echo hello
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: step 1 is missing "name"')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "raises when a step is missing run" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Missing command
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: step 1 is missing "run"')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "raises when a step has a blank name" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: "   "
            run: echo hello
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 has a blank name")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "raises when a step has a blank run command" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Blank command
            run: "   "
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 has a blank run command")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "uses safe YAML parsing and rejects aliases" do
      path, directory = write_config(<<~YAML)
        defaults: &defaults
          name: Reused
          run: echo hi
        name: Alias Pipeline
        steps:
          - <<: *defaults
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, /Invalid YAML/)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "uses safe YAML parsing and rejects arbitrary Ruby objects" do
      path, directory = write_config(<<~YAML)
        --- !ruby/object:Object
        steps:
          - name: Unsafe
            run: echo unsafe
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, /Invalid YAML/)
    ensure
      FileUtils.remove_entry(directory)
    end

    it "raises when the top-level configuration is not a mapping" do
      path, directory = write_config("- echo hello\n")

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: expected a mapping at the top level")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects blank environment variable names" do
      path, directory = write_config(<<~YAML)
        env:
          ? "   "
          : value
        steps:
          - name: Step
            run: echo hi
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: global env contains a blank environment variable name")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects non-string environment variable names" do
      path, directory = write_config(<<~YAML)
        env:
          123: value
        steps:
          - name: Step
            run: echo hi
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: global env contains a non-string environment variable name")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects invalid environment variable names" do
      path, directory = write_config(<<~YAML)
        env:
          APP-NAME: value
        steps:
          - name: Step
            run: echo hi
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: global env variable "APP-NAME" must use a valid environment variable name')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects environment variable names containing equals signs" do
      path, directory = write_config(<<~YAML)
        env:
          APP=VALUE: value
        steps:
          - name: Step
            run: echo hi
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: global env variable "APP=VALUE" must not contain =')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects null environment values" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            env:
              DATABASE:
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: step 1 env variable "DATABASE" must not be null')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects mapping environment values" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            env:
              DATABASE:
                nested: value
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: step 1 env variable "DATABASE" must contain a scalar value')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects array environment values" do
      path, directory = write_config(<<~YAML)
        env:
          DATABASE:
            - primary
        steps:
          - name: Step
            run: echo hi
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: global env variable "DATABASE" must contain a scalar value')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects null bytes in environment variable names" do
      path, directory = write_config("env:\n  \"BAD\\0NAME\": value\nsteps:\n  - name: Step\n    run: echo hi\n")

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: global env variable name contains a null byte")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects null bytes in environment variable values" do
      path, directory = write_config("env:\n  BAD: \"bad\\0value\"\nsteps:\n  - name: Step\n    run: echo hi\n")

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, 'Invalid pipeline configuration: global env variable "BAD" contains a null byte')
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects zero timeout" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            timeout: 0
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 timeout must be greater than 0")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects negative timeout" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            timeout: -1
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 timeout must be greater than 0")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects string timeout" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            timeout: "10"
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 timeout must be a positive number")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects boolean timeout" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            timeout: true
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 timeout must be a positive number")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects null timeout" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            timeout:
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 timeout must be a positive number")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects array timeout" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            timeout:
              - 1
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 timeout must be a positive number")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects mapping timeout" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            timeout:
              seconds: 1
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 timeout must be a positive number")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects negative retries" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retries: -1
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retries must be a non-negative integer")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects decimal retries" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retries: 1.5
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retries must be a non-negative integer")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects string retries" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retries: "2"
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retries must be a non-negative integer")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects boolean retries" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retries: true
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retries must be a non-negative integer")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects null retries" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retries:
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retries must be a non-negative integer")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects array retries" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retries:
              - 1
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retries must be a non-negative integer")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects mapping retries" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retries:
              count: 1
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retries must be a non-negative integer")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects negative retry delay" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retry_delay: -0.1
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retry_delay must be a non-negative number")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects invalid retry delay types" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retry_delay: "1"
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retry_delay must be a non-negative number")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects boolean retry delay" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retry_delay: false
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retry_delay must be a non-negative number")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects null retry delay" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retry_delay:
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retry_delay must be a non-negative number")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects array retry delay" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retry_delay:
              - 1
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retry_delay must be a non-negative number")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "rejects mapping retry delay" do
      path, directory = write_config(<<~YAML)
        steps:
          - name: Step
            run: echo hi
            retry_delay:
              seconds: 1
      YAML

      expect { loader_for(path).load }
        .to raise_error(MiniCi::ConfigurationError, "Invalid pipeline configuration: step 1 retry_delay must be a non-negative number")
    ensure
      FileUtils.remove_entry(directory)
    end

    it "returns environment hashes that cannot be unexpectedly mutated" do
      path, directory = write_config(<<~YAML)
        env:
          APP_ENV: test
        steps:
          - name: Step
            run: echo hi
            env:
              APP_ENV: integration
      YAML

      config = loader_for(path).load

      expect(config.env).to be_frozen
      expect(config.steps.first.env).to be_frozen
    ensure
      FileUtils.remove_entry(directory)
    end
  end
end
