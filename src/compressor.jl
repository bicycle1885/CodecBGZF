# BGZF Compressor
# ===============

struct BGZFCompressor <: TranscodingStreams.Codec
    zstream::CodecZlib.ZStream
    level::Int
    windowbits::Int
end

function BGZFCompressor(;level::Integer=CodecZlib.Z_DEFAULT_COMPRESSION,
                         windowbits::Integer=CodecZlib.Z_DEFAULT_WINDOWBITS)
    return BGZFCompressor(CodecZlib.ZStream(), level, windowbits+16)
end

function Base.show(io::IO, codec::BGZFCompressor)
    print(io, summary(codec), "(level=$(codec.level),windowbits=$(codec.windowbits))")
end

const BGZFCompressorStream{S} = TranscodingStream{BGZFCompressor,S} where S<:IO

function BGZFCompressorStream(stream::IO)
    return TranscodingStream(BGZFCompressor(), stream; bufsize=BGZF_MAX_BLOCK_SIZE)
end

const EOF_BLOCK = [
    0x1f, 0x8b, 0x08, 0x04, 0x00, 0x00, 0x00, 0x00,
    0x00, 0xff, 0x06, 0x00, 0x42, 0x43, 0x02, 0x00,
    0x1b, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00
]

function Base.close(stream::BGZFCompressorStream)
    if stream.state.mode != :panic
        TranscodingStreams.changemode!(stream, :close)
    end
    @assert write(stream.stream, EOF_BLOCK) == 28
    close(stream.stream)
    return nothing
end


# Methods
# -------

function TranscodingStreams.initialize(codec::BGZFCompressor)
    code = CodecZlib.deflate_init!(codec.zstream, codec.level, codec.windowbits)
    if code != CodecZlib.Z_OK
        CodecZlib.zerror(codec.zstream, code)
    end
    return
end

function TranscodingStreams.finalize(codec::BGZFCompressor)
    zstream = codec.zstream
    if zstream.state != C_NULL
        code = CodecZlib.deflate_end!(zstream)
        if code != CodecZlib.Z_OK
            CodecZlib.zerror(zstream, code)
        end
    end
    return
end

function TranscodingStreams.minoutsize(::BGZFCompressor, ::Memory)
    return Int(BGZF_MAX_BLOCK_SIZE)
end

function TranscodingStreams.process(codec::BGZFCompressor, input::Memory, output::Memory, error::Error)
    zstream = codec.zstream
    code = CodecZlib.deflate_reset!(zstream)
    if code != CodecZlib.Z_OK
        error[] = ErrorException(CodecZlib.zlib_error_message(zstream, code))
        return 0, 0, :error
    end
    zstream.next_in = input.ptr
    zstream.avail_in = min(input.size, BGZF_SAFE_BLOCK_SIZE)
    zstream.next_out = output.ptr + 8
    zstream.avail_out = output.size - 8
    code = CodecZlib.deflate!(zstream, CodecZlib.Z_FINISH)
    Δin = Int(input.size - zstream.avail_in)
    Δout = Int(output.size - 8 + zstream.avail_out)
    if code == CodecZlib.Z_STREAM_END
        # BGZF header (compatible with gzip)
        output[ 1] = 0x1f  # ID1
        output[ 2] = 0x8b  # ID2
        output[ 3] = 0x08  # CM
        output[ 4] = 0x04  # FLG
        output[ 5] = 0x00  # MTIME
        output[ 6] = 0x00  # MTIME
        output[ 7] = 0x00  # MTIME
        output[ 8] = 0x00  # MTIME
        output[ 9] = 0x00  # XFL
        output[10] = 0xff  # OS
        output[11] = 0x06  # XLEN
        output[12] = 0x00  # XLEN
        output[13] = 0x42  # SI1
        output[14] = 0x43  # SI2
        unsafe_store!(Ptr{UInt16}(output.ptr + 14), htol(0x0002))            # SLEN
        unsafe_store!(Ptr{UInt16}(output.ptr + 16), htol(UInt16(Δout - 1)))  # BSIZE
        return Δin, Δout + 8, :end
    elseif code == Z_OK
        error[] = ErrorException("failed to deflate")
    else
        error[] = ErrorException(CodecZlib.zlib_error_message(zstream, code))
    end
    return Δin, Δout, :error
end
