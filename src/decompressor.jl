# BGZF Decompressor
# =================

mutable struct BGZFDecompressor <: TranscodingStreams.Codec
    zstream::CodecZlib.ZStream
    windowbits::Int
    blockstart::Bool
end

function BGZFDecompressor(;windowbits::Integer=CodecZlib.Z_DEFAULT_WINDOWBITS)
    return BGZFDecompressor(CodecZlib.ZStream(), windowbits, true)
end

function Base.show(io::IO, codec::BGZFDecompressor)
    print(io, summary(codec), "(<windowbits=$(windowbits))")
end

const BGZFDecompressorStream{S} = TranscodingStream{BGZFDecompressor,S} where S<:IO

function BGZFDecompressorStream(stream::IO)
    return TranscodingStream(BGZFDecompressor(), stream; bufsize=BGZF_MAX_BLOCK_SIZE)
end

function Base.seek(stream::BGZFDecompressorStream, voffset::UInt64)
    TranscodingStreams.changemode!(stream, :read)
    seek(stream.stream, voffset >> 0xffff)
    skip(stream, voffset & 0xffff)
    return
end


# Methods
# -------

function TranscodingStreams.initialize(codec::BGZFDecompressor)
    code = CodecZlib.inflate_init!(codec.zstream, codec.windowbits+16)
    if code != CodecZlib.Z_OK
        CodecZlib.zerror(codec.zstream, code)
    end
    return
end

function TranscodingStreams.finalize(codec::BGZFDecompressor)
    zstream = codec.zstream
    if zstream.state != C_NULL
        code = CodecZlib.inflate_end!(zstream)
        if code != CodecZlib.Z_OK
            CodecZlib.zerror(zstream, code)
        end
    end
    return
end

function TranscodingStreams.minoutsize(::BGZFDecompressor, ::Memory)
    return Int(BGZF_MAX_BLOCK_SIZE)
end

function TranscodingStreams.process(codec::BGZFDecompressor, input::Memory, output::Memory, error::Error)
    zstream = codec.zstream
    if codec.blockstart
        code = CodecZlib.inflate_reset!(zstream)
        if code != CodecZlib.Z_OK
            error[] = ErrorException(CodecZlib.zlib_error_message(zstream, code))
            return 0, 0, :error
        end
    end
    zstream.next_in = input.ptr
    zstream.avail_in = input.size
    zstream.next_out = output.ptr
    zstream.avail_out = output.size
    code = CodecZlib.inflate!(zstream, CodecZlib.Z_NO_FLUSH)
    Δin = Int(input.size - zstream.avail_in)
    Δout = Int(output.size - zstream.avail_out)
    if code == CodecZlib.Z_OK
        codec.blockstart = false
        return Δin, Δout, :ok
    elseif code == CodecZlib.Z_STREAM_END
        codec.blockstart = true
        return Δin, Δout, :end
    else
        error[] = ErrorException(CodecZlib.zlib_error_message(zstream, code))
        return Δin, Δout, :error
    end
end
