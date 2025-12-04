using StringEncodings

export parseraw!

mutable struct RawParsed
	rawpath :: AbstractString
	parsed :: Bool
	possible_encoding
	flags
	numvars
	numpoints
	time_offset
	time_series
	runindices
	tracenames
	tracedict
	tracedata
	RawParsed(path) = new(path, false) # This is super cursed but the entire codebase is stateful so I will continue the tradition
end

abstract type RawLine end
abstract type RawHeader <: RawLine end
struct RawTitle <: RawHeader end
abstract type RawFooter <: RawLine end
struct RawDate <: RawFooter end
struct Flags <: RawFooter end
struct NoVariables <: RawFooter end
struct Points <: RawFooter end
struct Offset <: RawFooter end
struct Variables <: RawFooter end
struct Binary <: RawFooter end

const POSSIBLEENCODINGS = [enc"UTF-16LE",enc"UTF-8",enc"windows-1252"]
function checkencoding(line, pattern)
	for enc in POSSIBLEENCODINGS
		try
			decd = decode(line, enc)
			occursin(pattern, decd) && return enc
		catch
		end
	end
	error("No matching encoding found.")
end

const rawdateregex = r"Date:\s*(.*?)\s*$"
function parseline!(x::LTspiceSimulation, ::RawDate, line::AbstractString)
	m = match(rawdateregex,line)
	if m!==nothing
		try
			x.status.timestamp = DateTime(m.captures[1],"e u d HH:MM:SS yyyy")
		catch
			x.status.timestamp = DateTime(m.captures[1],"e u  d HH:MM:SS yyyy")
		end
		return true
	else
		return false
	end
end

const flagregex = r"^Flags:\s+([\w\s]+)$"
function parseline!(x::LTspiceSimulation, ::Flags, line::AbstractString)
	m = match(flagregex,line)
	m === nothing && return false

	x.rawfileparsed.flags = split(m.captures[1])
	return true
end

const novarregex = r"^No. Variables:(.+)$"
function parseline!(x::LTspiceSimulation, ::NoVariables, line::AbstractString)
	m = match(novarregex,line)
	m === nothing && return false

	x.rawfileparsed.numvars = parse(Int, m.captures[1])
	return true
end

const nopointsregex = r"^No. Points:(.+)$"
function parseline!(x::LTspiceSimulation, ::Points, line::AbstractString)
	m = match(nopointsregex,line)
	m === nothing && return false

	x.rawfileparsed.numpoints = parse(Int, m.captures[1])
	return true
end

const offsetregex = r"^Offset:(.+)$"
function parseline!(x::LTspiceSimulation, ::Offset, line::AbstractString)
	m = match(offsetregex,line)
	m === nothing && return false

	x.rawfileparsed.time_offset = parse(Float64, m.captures[1])
	return true
end

const varlabelregex = r"^Variables:.*$"
const varentryregex = r"^\s*(\d)\s*([\w\(\)]+)\s*(\w+)$"
function parseline!(x::LTspiceSimulation, ::Variables, line::AbstractString)
	m = match(varlabelregex,line)
	m !== nothing && return true
	
	m = match(varentryregex,line)
	m === nothing && return false

	num,name,unit = m.captures
	num = parse(Int, num)

	push!(x.rawfileparsed.tracenames, name)
	x.rawfileparsed.tracedict[name] = num

	return true
end

const binregex = r"^Binary:.*$"
function parseline!(x::LTspiceSimulation, ::Binary, line::AbstractString)
	m = match(binregex,line)
	m === nothing && return false
	return true
end


function parseraw!(x::LTspiceSimulation{Nparam,Nmeas,Nmdim,Nstep}) where {Nparam,Nmeas,Nmdim,Nstep}
	try
		open(x.rawfileparsed.rawpath, x.rawfileencoding) do io
			# I'm just copying the pattern as the log parser
			processlines!(io, x, [RawDate()], [Flags()])
			processlines!(io, x, [NoVariables()], [Points()])
			processlines!(io, x, [Offset()], [Variables()])
			processlines!(io, x, [Variables()], [Binary()])
		end
	catch e
		@error e "An error occured please submit an MWE in an issue"
	end

	if !isempty(x.rawfileparsed.tracenames ∩ x.measurementnames)
		@warn "There are traces with the same name as measurements, this is a bad idea and you should change it"
	end

	open(x.rawfileparsed.rawpath) do io
		lastenc = x.rawfileencoding.encodings[x.rawfileencoding.lastcorrectencoding]
		
		readuntil(io, encode("Binary:\n", lastenc))
		data = read(io)
		# Julia is column major order so each data point is one column
		data = reshape(data, :, x.rawfileparsed.numpoints)

		# The first 8 bytes are always the time data
		rawtime = reshape(reinterpret(Float64, @view data[1:8, :]), :)
		# LTspcie has a bug that makes time negative sometimes soooo
		for i in eachindex(rawtime)
			if rawtime[i] < 0.0
				rawtime[i] = abs(rawtime[i])
			end
		end

		# Lets hope LTspice doesn't start supporting arbatrary precision
		T = Float32
		if "complex" in x.rawfileparsed.flags
			# If the data has complex number values it inserts a row of zeros after time
			T = ComplexF64
			data = reinterpret(ComplexF64, @view data[17:end, :]) 
		else
			# LTspcie can either have single or double precision so we "guess" (not really)
			T = (size(data, 1)-8)÷(x.rawfileparsed.numvars-1) == 4 ? Float32 : Float64
			data = reinterpret(T, @view data[9:end, :])
		end

		if Nstep === 0
			x.rawfileparsed.runindices = [1]
			x.rawfileparsed.tracedata = data
			x.rawfileparsed.time_series = rawtime
			return nothing
		end
		
		runindices = x.rawfileparsed.runindices = findall(==(0.0), rawtime[:])
		@assert length(runindices) == prod(length, x.stepvalues.values)

		output = fill(Array{T, 2}(undef,1,1), length.(x.stepvalues.values)...)
		time = fill([], length.(x.stepvalues.values)...)

		steplengths = length.(x.stepvalues.values)
		steplengthsperind = cumprod([1; steplengths[1:end-1]...])

		runind = 1
		for Ind in CartesianIndices(output)
			output[Ind] = data[:, runindices[runind]:runindices[runind+1]-1]
			time[Ind] = rawtime[runindices[runind]:runindices[runind+1]-1]
			runind += 1
			runind == length(runindices) && break
		end
		output[end] = data[:, runindices[end]:end]
		time[end] = rawtime[runindices[end]:end]

		x.rawfileparsed.tracedata = output
		x.rawfileparsed.time_series = time

		return nothing
	end
	x.rawfileparsed.parsed = true
	return nothing
end