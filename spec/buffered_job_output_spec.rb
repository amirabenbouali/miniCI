# frozen_string_literal: true

RSpec.describe MiniCi::BufferedJobOutput do
  after { @buffer&.close }

  it "returns UTF-8 encoded content" do
    @buffer = described_class.new
    @buffer.io.write("plain output\n")

    expect(@buffer.string.encoding).to eq(Encoding::UTF_8)
  end

  it "reads non-ASCII output correctly even when the process default external encoding is not UTF-8" do
    with_default_external_encoding("US-ASCII") do
      @buffer = described_class.new
      @buffer.io.write("✓ Passed in 0.11s\n")

      expect(@buffer.string).to eq("✓ Passed in 0.11s\n")
      expect(@buffer.string.encoding).to eq(Encoding::UTF_8)
    end
  end

  it "scrubs invalid byte sequences instead of raising" do
    @buffer = described_class.new
    # Written at the raw file level (bypassing the Ruby IO's own encoding
    # conversion) to mimic how a subprocess writes arbitrary bytes when its
    # stdout/stderr is redirected straight to this Tempfile's descriptor.
    File.binwrite(@buffer.io.path, "valid before \xFF\xFE")

    expect { @buffer.string }.not_to raise_error
    expect(@buffer.string.valid_encoding?).to be(true)
  end
end
