# frozen_string_literal: true

require "json"
require "securerandom"
require "sinatra/base"

require_relative "../run_repository"
require_relative "configuration"
require_relative "presenter"
require_relative "run_launcher"

module MiniCi
  module Dashboard
    class App < Sinatra::Base
      set :root, File.expand_path("../../..", __dir__)
      set :views, proc { File.join(root, "views") }
      set :public_folder, proc { File.join(root, "public") }
      set :sessions, true
      set :show_exceptions, false

      configure do
        set :repository, RunRepository.new(workspace: Dir.pwd)
        set :presenter, Presenter.new(repository: settings.repository)
        set :launcher, RunLauncher.new(repository: settings.repository)
      end

      before do
        headers(
          "Content-Security-Policy" => "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'",
          "X-Content-Type-Options" => "nosniff",
          "Referrer-Policy" => "no-referrer"
        )
      end

      helpers do
        def h(value)
          Rack::Utils.escape_html(value.to_s)
        end

        def presenter
          settings.presenter
        end

        def csrf_token
          session[:csrf] ||= SecureRandom.hex(16)
        end

        def verify_csrf!
          halt 403, "Invalid CSRF token" unless params["csrf_token"] == session[:csrf]
        end

        def repository
          settings.repository
        end
      end

      get "/" do
        @runs = repository.list(page: 1, per_page: 10)
        @summary = presenter.summary(repository.all_records)
        @corrupt_count = repository.corrupt_count
        erb :index
      end

      get "/runs" do
        @status = params["status"].to_s
        @pipeline = params["pipeline"].to_s
        @page = [params["page"].to_i, 1].max
        @runs = repository.list(status: @status, pipeline: @pipeline, page: @page)
        erb :runs
      end

      get "/runs/:run_id" do
        @run = repository.load(params[:run_id])
        erb :run
      rescue MiniCi::Error => e
        @message = e.message
        status 404
        erb :error
      end

      get "/runs/:run_id/jobs/:job_index" do
        @run = repository.load(params[:run_id])
        @job = Array(@run["jobs"]).find { |job| job["index"].to_i == params[:job_index].to_i }
        halt 404, "Job not found" unless @job
        erb :job
      end

      get "/runs/:run_id/output" do
        @run = repository.load(params[:run_id])
        @output = File.read(repository.output_path(params[:run_id]))
        erb :output
      rescue MiniCi::Error, SystemCallError => e
        @message = e.message
        status 404
        erb :error
      end

      get "/runs/:run_id/artifacts/?" do
        artifact_response(params[:run_id], "")
      end

      get "/runs/:run_id/artifacts/*" do
        artifact_response(params[:run_id], params["splat"].first)
      end

      get "/run/new" do
        erb :new_run
      end

      post "/runs" do
        verify_csrf!
        record = settings.launcher.submit(
          pipeline_file: params["pipeline_file"],
          concurrency: params["concurrency"],
          no_cache: params["no_cache"] == "on",
          plugin_files: split_lines(params["plugin_files"]),
          plugin_dirs: split_lines(params["plugin_dirs"])
        )
        redirect "/runs/#{record.fetch("run_id")}"
      rescue MiniCi::Error => e
        @message = e.message
        status 422
        erb :error
      end

      post "/runs/:run_id/cancel" do
        verify_csrf!
        settings.launcher.cancel(params[:run_id])
        redirect "/runs/#{params[:run_id]}"
      end

      post "/runs/:run_id/delete" do
        verify_csrf!
        repository.delete(params[:run_id])
        redirect "/runs"
      rescue MiniCi::Error => e
        @message = e.message
        status 422
        erb :error
      end

      get "/api/runs" do
        content_type :json
        JSON.generate("runs" => repository.list(status: params["status"], pipeline: params["pipeline"]))
      end

      get "/api/runs/:run_id" do
        content_type :json
        JSON.generate(repository.load(params[:run_id]))
      rescue MiniCi::Error => e
        status 404
        JSON.generate("error" => e.message)
      end

      get "/api/runs/:run_id/events" do
        content_type :json
        JSON.generate(repository.events(params[:run_id], after: params["after"].to_i))
      rescue MiniCi::Error => e
        status 404
        JSON.generate("error" => e.message)
      end

      get "/api/runs/:run_id/output" do
        content_type :json
        offset = [params["offset"].to_i, 0].max
        JSON.generate(RunOutputWriter.new(repository.output_path(params[:run_id])).read_tail(offset: offset))
      rescue MiniCi::Error => e
        status 404
        JSON.generate("error" => e.message)
      end

      error do
        @message = env["sinatra.error"].message
        erb :error
      end

      def artifact_response(run_id, relative_path)
        record = repository.load(run_id)
        safe_path = repository.safe_artifact_path(record, relative_path)
        if File.directory?(safe_path)
          @run = record
          @relative_path = relative_path
          @entries = Dir.children(safe_path).sort
          erb :artifacts
        else
          content_type text_file?(safe_path) ? "text/plain" : "application/octet-stream"
          File.read(safe_path)
        end
      rescue MiniCi::Error, SystemCallError => e
        @message = e.message
        status 404
        erb :error
      end

      def text_file?(path)
        File.size(path) < 512 * 1024 && File.read(path, 1024).valid_encoding?
      rescue SystemCallError
        false
      end

      def split_lines(value)
        value.to_s.lines.map(&:strip).reject(&:empty?)
      end
    end
  end
end
