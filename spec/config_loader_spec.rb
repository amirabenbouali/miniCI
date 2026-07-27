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
