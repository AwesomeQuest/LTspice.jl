

"""
		PossibleEncodings

**fields**
- `encodings`           -- Array of encodings to try
- `iscorrectencoding`   -- callable object
- `lastcorrectencoding` -- index of correct encoding last time open was called
"""
mutable struct PossibleEncodings
	encodings :: Array{StringEncodings.Encodings.Encoding,1}
	iscorrectencoding :: Function
	lastcorrectencoding :: Int
	io :: IO
	PossibleEncodings(enc,ice) = new(enc,ice,0,IOStream(""))
end

function iscorrectencoding_logfile(io)
	firstline = readline(io)
	if occursin("Circuit: ", firstline) || occursin("LTspice ", firstline)
		return true
	else
		return false
	end
end

function iscorrectencoding_rawfile(io)
	firstline = readline(io)
	if occursin("Title: ", firstline)
		return true
	else
		return false
	end
end

const RAW_HEADER_ENCODINGS = [enc"UTF-16LE", enc"UTF-8", enc"windows-1252"]

function detect_raw_header_encoding(io::IO; encodings=RAW_HEADER_ENCODINGS)
	initial_position = position(io)
	prefix = read(io, 256)
	seek(io, initial_position)

	for encoding in encodings
		title_marker = encode("Title: ", encoding)
		if length(prefix) >= length(title_marker) &&
			@view(prefix[1:length(title_marker)]) == title_marker
			return encoding
		end
	end

	throw(ArgumentError("raw-file header does not begin with a supported encoding of 'Title: '"))
end

function tryopen!(fname::AbstractString, enc::PossibleEncodings, i)
	try_io = open(fname,enc.encodings[i])
	if try_io!==nothing
		if enc.iscorrectencoding(try_io)
			close(try_io.stream)  # ???
			enc.io = open(fname,enc.encodings[i])
			return true
		else
			close(try_io.stream)  # ???
		end
	end
	return false
end

function Base.open(fname::AbstractString, enc::PossibleEncodings)
	if enc.lastcorrectencoding != 0 &&
		 tryopen!(fname,enc,enc.lastcorrectencoding)
		return enc.io
	end
	for i in eachindex(enc.encodings)
		if i!=enc.lastcorrectencoding && tryopen!(fname,enc,i)
			enc.lastcorrectencoding = i
			return enc.io
		end
	end
	throw(ErrorException("no valid encoding found for $fname"))
end
