# frozen_string_literal: true

require "json"
require "securerandom"
require "sinatra/base"

require_relative "../run_repository"
require_relative "../version"
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

        def current_path
          request.path_info
        end

        def nav_item(label, href, icon)
          active = href == "/" ? current_path == "/" : current_path.start_with?(href)
          class_name = active ? "nav-link active" : "nav-link"
          %(<a class="#{class_name}" href="#{href}" #{active ? 'aria-current="page"' : ""}>#{dashboard_icon(icon)}<span>#{h(label)}</span></a>)
        end

        def status_badge(status)
          value = status.to_s.empty? ? "pending" : status.to_s
          %(<span class="status-badge status-#{h(value)}">#{dashboard_icon(status_icon(value))}<span>#{h(presenter.status_label(value))}</span></span>)
        end

        def dashboard_icon(name)
          icons = {
            "artifact" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7.5 12 3l8 4.5v9L12 21l-8-4.5v-9Z"/><path d="m4 7.5 8 4.5 8-4.5"/><path d="M12 12v9"/></svg>),
            "cancel" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>),
            "check" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m20 6-11 11-5-5"/></svg>),
            "clock" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>),
            "copy" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="9" width="10" height="10" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v1"/></svg>),
            "fail" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/></svg>),
            "home" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m3 11 9-8 9 8"/><path d="M5 10v10h14V10"/><path d="M9 20v-6h6v6"/></svg>),
            "play" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m8 5 11 7-11 7V5Z"/></svg>),
            "refresh" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 11a8 8 0 0 0-14.9-4"/><path d="M4 5v5h5"/><path d="M4 13a8 8 0 0 0 14.9 4"/><path d="M20 19v-5h-5"/></svg>),
            "runs" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16"/><path d="M4 12h16"/><path d="M4 18h16"/></svg>),
            "skip" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 4 10 8-10 8V4Z"/><path d="M19 5v14"/></svg>),
            "terminal" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m4 7 5 5-5 5"/><path d="M11 17h9"/></svg>),
            "timer" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 2h4"/><path d="M12 14v-4"/><circle cx="12" cy="14" r="8"/></svg>),
            "trash" => %(<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/></svg>)
          }
          icons.fetch(name.to_s, %(<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8"/></svg>))
        end

        def status_icon(status)
          case status.to_s
          when "passed" then "check"
          when "failed", "internal_error", "timed_out" then "fail"
          when "cancelled" then "cancel"
          when "skipped" then "skip"
          else "clock"
          end
        end
      end

      get "/" do
        @page_title = "Overview"
        @runs = repository.list(page: 1, per_page: 10)
        @summary = presenter.summary(repository.all_records)
        @corrupt_count = repository.corrupt_count
        erb :index
      end

      get "/runs" do
        @page_title = "Runs"
        @status = params["status"].to_s
        @pipeline = params["pipeline"].to_s
        @page = [params["page"].to_i, 1].max
        @runs = repository.list(status: @status, pipeline: @pipeline, page: @page)
        erb :runs
      end

      get "/runs/:run_id" do
        @run = repository.load(params[:run_id])
        @page_title = @run["pipeline_name"] || @run["pipeline_file"] || "Run detail"
        erb :run
      rescue MiniCi::Error => e
        @page_title = "Error"
        @message = e.message
        status 404
        erb :error
      end

      get "/runs/:run_id/jobs/:job_index" do
        @run = repository.load(params[:run_id])
        @job = Array(@run["jobs"]).find { |job| job["index"].to_i == params[:job_index].to_i }
        halt 404, "Job not found" unless @job
        @page_title = @job["name"] || "Job detail"
        erb :job
      end

      get "/runs/:run_id/output" do
        @run = repository.load(params[:run_id])
        @output = File.read(repository.output_path(params[:run_id]), encoding: Encoding::UTF_8).scrub
        @page_title = "Output log"
        erb :output
      rescue MiniCi::Error, SystemCallError => e
        @page_title = "Error"
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
        @page_title = "New run"
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
        @page_title = "Error"
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
        @page_title = "Error"
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
          @page_title = "Artifacts"
          erb :artifacts
        else
          is_text = text_file?(safe_path)
          content_type is_text ? "text/plain" : "application/octet-stream"
          is_text ? File.read(safe_path, encoding: Encoding::UTF_8).scrub : File.binread(safe_path)
        end
      rescue MiniCi::Error, SystemCallError => e
        @page_title = "Error"
        @message = e.message
        status 404
        erb :error
      end

      def text_file?(path)
        File.size(path) < 512 * 1024 && File.read(path, 1024, encoding: Encoding::UTF_8).valid_encoding?
      rescue SystemCallError
        false
      end

      def split_lines(value)
        value.to_s.lines.map(&:strip).reject(&:empty?)
      end
    end
  end
end
