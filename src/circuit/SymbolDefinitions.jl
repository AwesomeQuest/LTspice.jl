export SymbolPin, SymbolDefinition, SymbolLibrary
export default_symbol_search_paths, find_symbol_definition
export read_symbol_definition, load_symbol_definition, pin_position

"""
A pin declared by an LTspice `.asy` symbol definition.

`position` is relative to the symbol origin. `spice_order` is the terminal
number used by the generated SPICE netlist.
"""
struct SymbolPin
    position::NTuple{2,Int}
    name::Union{Nothing,String}
    spice_order::Int
end

"""
A parsed LTspice `.asy` symbol definition.
"""
struct SymbolDefinition
    name::String
    path::String
    pins::Vector{SymbolPin}
end

"""
A lazily loaded collection of LTspice symbol definitions.

Search paths are ordered. The first matching symbol definition wins, matching
LTspice's local/custom-library precedence over installed libraries.
"""
mutable struct SymbolLibrary
    search_paths::Vector{String}
    cache::Dict{String,SymbolDefinition}
end

function _normalise_symbol_path(path::AbstractString)
    normalised = replace(String(path), '\\' => '/')
    normalised = replace(normalised, r"/+" => "/")
    normalised = strip(normalised, '/')
    endswith(lowercase(normalised), ".asy") &&
        (normalised = normalised[1:end-4])
    return normalised
end

function _push_existing_unique!(paths::Vector{String}, path::AbstractString)
    expanded = abspath(expanduser(path))
    isdir(expanded) || return paths
    expanded in paths || push!(paths, expanded)
    return paths
end

function _wine_prefix()
    return get(ENV, "WINEPREFIX", joinpath(homedir(), ".wine"))
end

function _wine_user_names(prefix::AbstractString)
    users_directory = joinpath(prefix, "drive_c", "users")
    isdir(users_directory) || return String[]

    return filter(readdir(users_directory)) do name
        lowercase(name) != "public" && isdir(joinpath(users_directory, name))
    end
end

"""
    default_symbol_search_paths(; schematic_path=nothing,
                                  executable_path=nothing,
                                  additional_paths=[])

Return existing LTspice symbol directories in lookup order.

The search covers:

1. The schematic directory and its `lib/sym` subdirectory.
2. Caller-provided custom symbol directories.
3. Current LTspice user-library locations.
4. Legacy LTspice XVII and LTspice IV user-library locations.
5. Symbol directories relative to the detected executable.
6. Standard installation directories for Windows, macOS, and Wine.

Only directories that currently exist are returned.
"""
function default_symbol_search_paths(;
    schematic_path::Union{Nothing,AbstractString}=nothing,
    executable_path::Union{Nothing,AbstractString}=nothing,
    additional_paths=AbstractString[],
)
    paths = String[]

    if schematic_path !== nothing
        schematic_directory =
            isdir(schematic_path) ? String(schematic_path) : dirname(abspath(schematic_path))
        _push_existing_unique!(paths, schematic_directory)
        _push_existing_unique!(paths, joinpath(schematic_directory, "lib", "sym"))
    end

    for path in additional_paths
        _push_existing_unique!(paths, path)
    end

    if Sys.iswindows()
        local_app_data = get(ENV, "LOCALAPPDATA", "")
        user_profile = get(ENV, "USERPROFILE", homedir())

        isempty(local_app_data) ||
            _push_existing_unique!(paths, joinpath(local_app_data, "LTspice", "lib", "sym"))
        _push_existing_unique!(
            paths,
            joinpath(user_profile, "Documents", "LTspiceXVII", "lib", "sym"),
        )
        _push_existing_unique!(
            paths,
            joinpath(user_profile, "Documents", "LTspiceIV", "lib", "sym"),
        )
    elseif Sys.isapple()
        _push_existing_unique!(
            paths,
            joinpath(homedir(), "Library", "Application Support", "LTspice", "lib", "sym"),
        )
        _push_existing_unique!(
            paths,
            joinpath(homedir(), "Documents", "LTspice", "lib", "sym"),
        )
    elseif Sys.islinux()
        prefix = _wine_prefix()
        for user_name in _wine_user_names(prefix)
            wine_home = joinpath(prefix, "drive_c", "users", user_name)
            _push_existing_unique!(
                paths,
                joinpath(wine_home, "AppData", "Local", "LTspice", "lib", "sym"),
            )
            _push_existing_unique!(
                paths,
                joinpath(wine_home, "Documents", "LTspiceXVII", "lib", "sym"),
            )
            _push_existing_unique!(
                paths,
                joinpath(wine_home, "Documents", "LTspiceIV", "lib", "sym"),
            )
            _push_existing_unique!(
                paths,
                joinpath(wine_home, "My Documents", "LTspiceXVII", "lib", "sym"),
            )
            _push_existing_unique!(
                paths,
                joinpath(wine_home, "My Documents", "LTspiceIV", "lib", "sym"),
            )
        end
    end

    if executable_path === nothing
        executable_path = try
            defaultltspiceexecutable()
        catch
            nothing
        end
    end

    if executable_path !== nothing
        executable_directory = dirname(abspath(executable_path))
        _push_existing_unique!(paths, joinpath(executable_directory, "lib", "sym"))
        _push_existing_unique!(paths, joinpath(dirname(executable_directory), "lib", "sym"))

        if Sys.isapple() && occursin(".app", executable_path)
            application_path = first(split(String(executable_path), ".app")) * ".app"
            _push_existing_unique!(
                paths,
                joinpath(application_path, "Contents", "Resources", "lib", "sym"),
            )
            _push_existing_unique!(
                paths,
                joinpath(application_path, "Contents", "lib", "sym"),
            )
        end
    end

    if Sys.iswindows()
        program_files = get(ENV, "ProgramFiles", raw"C:\Program Files")
        program_files_x86 = get(ENV, "ProgramFiles(x86)", raw"C:\Program Files (x86)")

        for path in (
            joinpath(program_files, "ADI", "LTspice", "lib", "sym"),
            joinpath(program_files, "LTC", "LTspiceXVII", "lib", "sym"),
            joinpath(program_files, "LTC", "LTspiceIV", "lib", "sym"),
            joinpath(program_files_x86, "LTC", "LTspiceIV", "lib", "sym"),
        )
            _push_existing_unique!(paths, path)
        end
    elseif Sys.islinux()
        drive_c = joinpath(_wine_prefix(), "drive_c")
        for path in (
            joinpath(drive_c, "Program Files", "ADI", "LTspice", "lib", "sym"),
            joinpath(drive_c, "Program Files", "LTC", "LTspiceXVII", "lib", "sym"),
            joinpath(drive_c, "Program Files", "LTC", "LTspiceIV", "lib", "sym"),
            joinpath(drive_c, "Program Files (x86)", "LTC", "LTspiceIV", "lib", "sym"),
        )
            _push_existing_unique!(paths, path)
        end
    end

    return paths
end

SymbolLibrary(;
    schematic_path::Union{Nothing,AbstractString}=nothing,
    executable_path::Union{Nothing,AbstractString}=nothing,
    additional_paths=AbstractString[],
) = SymbolLibrary(
    default_symbol_search_paths(;
        schematic_path=schematic_path,
        executable_path=executable_path,
        additional_paths=additional_paths,
    ),
    Dict{String,SymbolDefinition}(),
)

SymbolLibrary(search_paths::AbstractVector{<:AbstractString}) = SymbolLibrary(
    unique(abspath.(expanduser.(String.(search_paths)))),
    Dict{String,SymbolDefinition}(),
)

"""
    find_symbol_definition(library, name) -> String

Find the `.asy` file for `name`. Names may include LTspice library
subdirectories, for example `"ADC/AD4000"`. Matching is case-insensitive when
the host filesystem is case-sensitive.
"""
function find_symbol_definition(library::SymbolLibrary, name::AbstractString)
    relative_name = _normalise_symbol_path(name)
    isempty(relative_name) && throw(ArgumentError("symbol name cannot be empty"))
    relative_parts = split(relative_name, '/')

    for search_path in library.search_paths
        candidate = joinpath(search_path, relative_parts...) * ".asy"
        isfile(candidate) && return candidate

        directory = search_path
        matched = true
        for part in relative_parts[1:end-1]
            entry = findfirst(entry -> lowercase(entry) == lowercase(part), readdir(directory))
            if entry === nothing || !isdir(joinpath(directory, readdir(directory)[entry]))
                matched = false
                break
            end
            directory = joinpath(directory, readdir(directory)[entry])
        end
        matched || continue

        filename = relative_parts[end] * ".asy"
        entries = readdir(directory)
        entry = findfirst(entry -> lowercase(entry) == lowercase(filename), entries)
        entry === nothing || return joinpath(directory, entries[entry])
    end

    filename = lowercase(relative_parts[end] * ".asy")
    basename_matches = String[]
    for search_path in library.search_paths
        for (directory, _, files) in walkdir(search_path)
            for file in files
                lowercase(file) == filename || continue
                push!(basename_matches, joinpath(directory, file))
            end
        end
        length(basename_matches) == 1 && return only(basename_matches)
        isempty(basename_matches) || break
    end

    if length(basename_matches) > 1
        throw(ArgumentError(
            "LTspice symbol '$name' is ambiguous. Matches: " *
            join(basename_matches, ", "),
        ))
    end

    throw(ArgumentError(
        "Could not find LTspice symbol '$name'. Searched: " *
        join(library.search_paths, ", "),
    ))
end

mutable struct _PendingSymbolPin
    position::NTuple{2,Int}
    name::Union{Nothing,String}
    spice_order::Union{Nothing,Int}
end

function _finish_pin!(
    pins::Vector{SymbolPin},
    pending::Union{Nothing,_PendingSymbolPin},
    path::AbstractString,
)
    pending === nothing && return
    pending.spice_order === nothing &&
        throw(ArgumentError("PIN is missing SpiceOrder in symbol definition: $path"))
    any(pin -> pin.spice_order == pending.spice_order, pins) &&
        throw(ArgumentError(
            "Duplicate SpiceOrder $(pending.spice_order) in symbol definition: $path",
        ))
    push!(pins, SymbolPin(pending.position, pending.name, pending.spice_order))
end

"""
    read_symbol_definition(path) -> SymbolDefinition

Parse pin positions, names, and SPICE terminal ordering from an LTspice `.asy`
symbol definition.
"""
function read_symbol_definition(path::AbstractString)
    isfile(path) || throw(ArgumentError("symbol definition does not exist: $path"))

    pins = SymbolPin[]
    pending = nothing

    encoding = circuitfileencoding(path)
    open(path, encoding) do io
        for line in eachline(io)
            fields = split(strip(line))
            isempty(fields) && continue

            if fields[1] == "PIN"
                length(fields) >= 3 ||
                    throw(ArgumentError("Malformed PIN record in symbol definition: $path"))
                _finish_pin!(pins, pending, path)
                pending = _PendingSymbolPin(
                    (parse(Int, fields[2]), parse(Int, fields[3])),
                    nothing,
                    nothing,
                )
            elseif fields[1] == "PINATTR"
                pending === nothing &&
                    throw(ArgumentError("PINATTR appears before PIN in symbol definition: $path"))
                length(fields) >= 3 ||
                    throw(ArgumentError("Malformed PINATTR record in symbol definition: $path"))

                attribute = fields[2]
                value = join(fields[3:end], " ")
                if attribute == "PinName"
                    pending.name = value
                elseif attribute == "SpiceOrder"
                    pending.spice_order = parse(Int, value)
                end
            end
        end
    end

    _finish_pin!(pins, pending, path)
    isempty(pins) && throw(ArgumentError("symbol definition contains no pins: $path"))
    sort!(pins; by=pin -> pin.spice_order)

    return SymbolDefinition(splitext(basename(path))[1], abspath(path), pins)
end

"""
    load_symbol_definition(library, name) -> SymbolDefinition

Resolve and lazily parse a symbol definition. Repeated requests use the
library cache.
"""
function load_symbol_definition(library::SymbolLibrary, name::AbstractString)
    key = lowercase(_normalise_symbol_path(name))
    return get!(library.cache, key) do
        read_symbol_definition(find_symbol_definition(library, name))
    end
end

function _transform_symbol_position(
    position::NTuple{2,Int},
    orientation::AbstractString,
)
    x, y = position
    orientation == "R0" && return (x, y)
    orientation == "R90" && return (-y, x)
    orientation == "R180" && return (-x, -y)
    orientation == "R270" && return (y, -x)
    orientation == "M0" && return (-x, y)
    orientation == "M90" && return (y, x)
    orientation == "M180" && return (x, -y)
    orientation == "M270" && return (-y, -x)
    throw(ArgumentError("unsupported LTspice orientation: $orientation"))
end

"""
    pin_position(definition, spice_order, component_position, orientation="R0")

Return the absolute schematic coordinate of a component pin.
"""
function pin_position(
    definition::SymbolDefinition,
    spice_order::Integer,
    component_position::Tuple{<:Integer,<:Integer},
    orientation::Union{Symbol,AbstractString}="R0",
)
    matches = filter(pin -> pin.spice_order == spice_order, definition.pins)
    length(matches) == 1 ||
        throw(ArgumentError(
            "symbol $(definition.name) has no unique pin with SpiceOrder $spice_order",
        ))

    offset = _transform_symbol_position(matches[1].position, string(orientation))
    return (Int(component_position[1]) + offset[1],
            Int(component_position[2]) + offset[2])
end