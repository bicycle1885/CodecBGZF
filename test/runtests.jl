using CodecBGZF
import TranscodingStreams:
    TranscodingStream,
    test_roundtrip_read,
    test_roundtrip_write,
    test_roundtrip_lines,
    test_roundtrip_transcode
using Base.Test

@testset "BGZF Codec" begin
    test_roundtrip_read(BGZFCompressorStream, BGZFDecompressorStream)
    test_roundtrip_write(BGZFCompressorStream, BGZFDecompressorStream)
    test_roundtrip_lines(BGZFCompressorStream, BGZFDecompressorStream)
    test_roundtrip_transcode(BGZFCompressor, BGZFDecompressor)
end
