# Block
# =====

# Internal details
# ----------------
#
# When reading data from an input, compressed data will be read to a buffer
# (compressed block) and then inflated into a decompressed block at a time.
# When writing data to an output, raw data will be deflated into a compressed
# block and then written to the output immediately.  Each data block is no
# larger than 64 KiB before and after compression.
#
# Read mode (stream.mode = READ_MODE)
# -----------------------------------
#
#          compressed block          decompressed block
# stream   +---------------+         +---------------+
# .io ---> |xxxxxxx        | ------> |xxxxxxxxxxx    | --->
#     read +---------------+ inflate +---------------+ read
#                                    |------>| block.position ∈ [0, 64K)
#                                    |--------->| block.size ∈ [0, 64K]
#
# Write mode (stream.mode = WRITE_MODE)
# -------------------------------------
#
#          compressed block          decompressed block
# stream   +---------------+         +---------------+
# .io <--- |xxxxxxx        | <------ |xxxxxxxx       | <---
#    write +---------------+ deflate +---------------+ write
#                                    |------>| block.position ∈ [0, 64K)
#                                    |------------->| block.size = 64K - 256
# - xxx: used data
# - 64K: 65536 (= BGZF_MAX_BLOCK_SIZE = 64 * 1024)

# BGZF blocks are no larger than 64 KiB before and after compression.
const BGZF_MAX_BLOCK_SIZE = UInt(64 * 1024)

# BGZF_MAX_BLOCK_SIZE minus "margin for safety"
# NOTE: Data block will become slightly larger after deflation when bytes are
# randomly distributed.
const BGZF_SAFE_BLOCK_SIZE = UInt(BGZF_MAX_BLOCK_SIZE - 256)

mutable struct Block
    # space for the compressed block
    compressed_block::Vector{UInt8}

    # space for the decompressed block
    decompressed_block::Vector{UInt8}

    # block offset in a file (this is always 0 for a pipe stream)
    block_offset::Int

    # the next reading byte position in a block
    position::Int

    # number of available bytes in the decompressed block
    size::Int

    # zstream object
    zstream::ZStream
end

function Block(mode::Symbol)
    zstream = ZStream()
    if mode == :inflate
        size = UInt(0)
        code = CodecZlib.inflate_init!(zstream, CodecZlib.Z_DEFAULT_WINDOWBITS)
        if code != CodecZlib.Z_OK
            CodecZlib.zerror(zstream, code)
        end
    elseif mode == :deflate
        size = BGZF_SAFE_BLOCK_SIZE
        code = CodecZlib.deflate_init!(zstream,
                                       CodecZlib.Z_DEFAULT_COMPRESSION,
                                       CodecZlib.Z_DEFAULT_WINDOWBITS)
        if code != CodecZlib.Z_OK
            CodecZlib.zerror(zstream, code)
        end
    else
        assert(false)
    end
    compressed_block = Vector{UInt8}(BGZF_MAX_BLOCK_SIZE)
    decompressed_block = Vector{UInt8}(BGZF_MAX_BLOCK_SIZE)
    return Block(compressed_block, decompressed_block, 0, 1, size, zstream)
end
