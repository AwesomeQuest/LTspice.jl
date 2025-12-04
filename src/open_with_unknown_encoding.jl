

"""
		PossibleEncodings

# Fields
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
