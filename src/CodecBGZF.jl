module CodecBGZF

export
    BGZFCompressor,
    BGZFCompressorStream,
    BGZFDecompressor,
    BGZFDecompressorStream

import CodecZlib
import TranscodingStreams:
    TranscodingStreams,
    TranscodingStream,
    Memory,
    Error,
    initialize,
    finalize

# BGZF blocks are no larger than 64 KiB before and after compression.
const BGZF_MAX_BLOCK_SIZE = UInt(64 * 1024)

# BGZF_MAX_BLOCK_SIZE minus "margin for safety"
# NOTE: Data block will become slightly larger after deflation when bytes are
# randomly distributed.
const BGZF_SAFE_BLOCK_SIZE = UInt(BGZF_MAX_BLOCK_SIZE - 256)

include("compressor.jl")
include("decompressor.jl")

end # module
