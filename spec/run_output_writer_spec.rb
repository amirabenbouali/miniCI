# frozen_string_literal: true

RSpec.describe MiniCi::RunOutputWriter do
  let(:directory) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(directory) if directory && File.directory?(directory)
  end

  it "appends output and reads incremental tails" do
    writer = described_class.new(File.join(directory, "output.log"))
    writer.puts("first")
    writer.print("second")

    first = writer.read_tail(offset: 0)
    second = writer.read_tail(offset: first.fetch("next_offset"))

    expect(first.fetch("text")).to include("first")
    expect(first.fetch("text")).to include("second")
    expect(second.fetch("text")).to eq("")
    expect(second.fetch("complete")).to be(true)
  end
end
