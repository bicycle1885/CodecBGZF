using CodecBGZF
import TranscodingStreams:
    TranscodingStream,
    test_roundtrip_read,
    test_roundtrip_write,
    test_roundtrip_lines,
    test_roundtrip_transcode
using Base.Test

@testset "BGZF Codec" begin
    # Test the EOF trailer (28 bytes).
    data = UInt8[]
    buffer = IOBuffer(data, true, true)
    stream = BGZFCompressorStream(buffer)
    write(stream, "foobar")
    data = buffer.data
    close(stream)
    @test sizeof(data) ≥ 28
    @test data[end-27:end] == [
        0x1f, 0x8b, 0x08, 0x04, 0x00, 0x00, 0x00, 0x00,
        0x00, 0xff, 0x06, 0x00, 0x42, 0x43, 0x02, 0x00,
        0x1b, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00]
    @test read(BGZFDecompressorStream(IOBuffer(data))) == b"foobar"

    test_roundtrip_read(BGZFCompressorStream, BGZFDecompressorStream)
    test_roundtrip_write(BGZFCompressorStream, BGZFDecompressorStream)
    test_roundtrip_lines(BGZFCompressorStream, BGZFDecompressorStream)
    test_roundtrip_transcode(BGZFCompressor, BGZFDecompressor)
end
