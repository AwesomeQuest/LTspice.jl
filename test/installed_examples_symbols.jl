using LTspice
using Test

const INSTALLED_EXAMPLE_MINIMUM_PIN_WIRE_MATCH = 0.90

# These bundled examples contain short, fully floating wire segments used for
# visual layout rather than electrical connectivity.
const INSTALLED_EXAMPLE_WIRE_AUDIT_EXCLUSIONS = Set([
    "Applications/LTC1267-ADJ.asc",
    "Applications/LT1533.asc",
    "Applications/LTM8026.asc",
    "Applications/LTM8052A.asc",
    "Applications/LT8610A.asc",
    "Applications/LT8610AB.asc",
    "Applications/LTC3720.asc",
])

_normalise_example_symbol_name(name::AbstractString) =
    lowercase(strip(replace(replace(String(name), '\\' => '/'), r"/+" => "/"), '/'))

function installed_example_directory()
    configured = get(ENV, "LTSPICE_EXAMPLES", "")
    isempty(configured) || return isdir(configured) ? abspath(configured) : nothing

    for symbol_path in default_symbol_search_paths()
        ltspice_directory = dirname(dirname(symbol_path))
        candidate = joinpath(ltspice_directory, "examples")
        isdir(candidate) && return candidate
    end

    return nothing
end

function installed_symbol_index(search_paths)
    paths_by_relative_name = Dict{String,String}()
    paths_by_basename = Dict{String,Vector{String}}()

    for search_path in search_paths
        for (directory, _, files) in walkdir(search_path)
            for file in files
                endswith(lowercase(file), ".asy") || continue

                path = joinpath(directory, file)
                relative_name =
                    _normalise_example_symbol_name(splitext(relpath(path, search_path))[1])
                get!(paths_by_relative_name, relative_name, path)

                basename_key = lowercase(splitext(file)[1])
                push!(get!(paths_by_basename, basename_key, String[]), path)
            end
        end
    end

    return paths_by_relative_name, paths_by_basename
end

function resolve_installed_symbol(
    name,
    paths_by_relative_name,
    paths_by_basename,
)
    key = _normalise_example_symbol_name(name)
    path = get(paths_by_relative_name, key, nothing)
    path !== nothing && return path

    candidates = get(paths_by_basename, lowercase(basename(key)), String[])
    length(candidates) == 1 && return only(candidates)
    return nothing
end

function parse_example_schematic(path)
    symbols = Tuple{String,NTuple{2,Int},String}[]
    wires = Tuple{NTuple{2,Int},NTuple{2,Int}}[]
    net_anchors = Set{NTuple{2,Int}}()

    for record in readcircuit(path).records
        fields = split(strip(record))
        isempty(fields) && continue

        if fields[1] == "SYMBOL" && length(fields) >= 5
            push!(
                symbols,
                (
                    fields[2],
                    (parse(Int, fields[3]), parse(Int, fields[4])),
                    fields[5],
                ),
            )
        elseif fields[1] == "WIRE" && length(fields) >= 5
            push!(
                wires,
                (
                    (parse(Int, fields[2]), parse(Int, fields[3])),
                    (parse(Int, fields[4]), parse(Int, fields[5])),
                ),
            )
        elseif fields[1] in ("FLAG", "IOPIN") && length(fields) >= 3
            push!(net_anchors, (parse(Int, fields[2]), parse(Int, fields[3])))
        end
    end

    return symbols, wires, net_anchors
end

function point_on_wire(point, wire)
    x, y = point
    (x1, y1), (x2, y2) = wire

    (x - x1) * (y2 - y1) == (y - y1) * (x2 - x1) || return false
    return min(x1, x2) <= x <= max(x1, x2) &&
           min(y1, y2) <= y <= max(y1, y2)
end

function wires_intersect(first_wire, second_wire)
    for point in first_wire
        point_on_wire(point, second_wire) && return true
    end
    for point in second_wire
        point_on_wire(point, first_wire) && return true
    end
    return false
end

function unaccounted_wire_networks(wires, pin_positions, net_anchors)
    isempty(wires) && return Vector{Vector{Int}}()

    parent = collect(eachindex(wires))

    function find_root(index)
        while parent[index] != index
            parent[index] = parent[parent[index]]
            index = parent[index]
        end
        return index
    end

    function union_wires!(first_index, second_index)
        first_root = find_root(first_index)
        second_root = find_root(second_index)
        first_root == second_root || (parent[second_root] = first_root)
    end

    for first_index in eachindex(wires)
        for second_index in (first_index + 1):length(wires)
            wires_intersect(wires[first_index], wires[second_index]) &&
                union_wires!(first_index, second_index)
        end
    end

    networks = Dict{Int,Vector{Int}}()
    for wire_index in eachindex(wires)
        push!(get!(networks, find_root(wire_index), Int[]), wire_index)
    end

    unaccounted = Vector{Vector{Int}}()
    for wire_indices in values(networks)
        network_wires = view(wires, wire_indices)
        touches_pin = any(
            point_on_wire(pin_position, wire)
            for pin_position in pin_positions
            for wire in network_wires
        )
        touches_anchor = any(
            point_on_wire(net_anchor, wire)
            for net_anchor in net_anchors
            for wire in network_wires
        )
        touches_pin || touches_anchor || push!(unaccounted, sort!(wire_indices))
    end

    return unaccounted
end

@testset "installed LTspice example symbol pins" begin
    examples = installed_example_directory()

    if examples === nothing
        @info "LTspice examples not found; skipping installed example symbol audit" *
              " (set LTSPICE_EXAMPLES to run it explicitly)"
        @test_skip false
    else
        search_paths = default_symbol_search_paths()
        paths_by_relative_name, paths_by_basename =
            installed_symbol_index(search_paths)
        definition_cache = Dict{String,Union{Nothing,SymbolDefinition}}()

        schematic_paths = sort([
            joinpath(directory, file)
            for (directory, _, files) in walkdir(examples)
            for file in files
            if endswith(lowercase(file), ".asc")
        ])

        schematic_count = 0
        symbol_count = 0
        resolved_symbol_count = 0
        pin_count = 0
        wired_pin_count = 0
        missing_symbols = Dict{String,Int}()
        invalid_symbols = Dict{String,Int}()
        orientation_counts = Dict{String,NTuple{2,Int}}()
        fully_resolved_schematic_count = 0
        audited_wire_count = 0
        unaccounted_wire_networks_by_schematic = Dict{String,Vector{Vector{Int}}}()

        for schematic_path in schematic_paths
            symbols, wires, net_anchors = parse_example_schematic(schematic_path)
            schematic_count += 1
            symbol_count += length(symbols)
            pin_positions = Set{NTuple{2,Int}}()
            schematic_symbols_resolved = true

            for (name, anchor, orientation) in symbols
                definition_path = resolve_installed_symbol(
                    name,
                    paths_by_relative_name,
                    paths_by_basename,
                )
                if definition_path === nothing
                    missing_symbols[name] = get(missing_symbols, name, 0) + 1
                    schematic_symbols_resolved = false
                    continue
                end

                definition = get!(definition_cache, definition_path) do
                    try
                        read_symbol_definition(definition_path)
                    catch error
                        invalid_symbols[name] = get(invalid_symbols, name, 0) + 1
                        @debug "Could not parse installed LTspice symbol" name definition_path error
                        nothing
                    end
                end
                if definition === nothing
                    schematic_symbols_resolved = false
                    continue
                end

                resolved_symbol_count += 1
                orientation_pin_count, orientation_wired_pin_count =
                    get(orientation_counts, orientation, (0, 0))

                for pin in definition.pins
                    position =
                        pin_position(definition, pin.spice_order, anchor, orientation)
                    push!(pin_positions, position)
                    is_wired = any(wire -> point_on_wire(position, wire), wires)

                    pin_count += 1
                    wired_pin_count += is_wired
                    orientation_pin_count += 1
                    orientation_wired_pin_count += is_wired
                end

                orientation_counts[orientation] =
                    (orientation_pin_count, orientation_wired_pin_count)
            end

            relative_schematic_path = relpath(schematic_path, examples)
            if schematic_symbols_resolved &&
               relative_schematic_path ∉ INSTALLED_EXAMPLE_WIRE_AUDIT_EXCLUSIONS
                fully_resolved_schematic_count += 1
                audited_wire_count += length(wires)
                networks = unaccounted_wire_networks(
                    wires,
                    pin_positions,
                    net_anchors,
                )
                isempty(networks) ||
                    (unaccounted_wire_networks_by_schematic[
                        relative_schematic_path
                    ] = networks)
            end
        end

        match_rate = wired_pin_count / pin_count
        orientation_match_rates = Dict(
            orientation => wired / total
            for (orientation, (total, wired)) in orientation_counts
        )

        @info "Installed LTspice example symbol audit" examples schematic_count symbol_count resolved_symbol_count pin_count wired_pin_count match_rate orientation_match_rates missing_symbols invalid_symbols fully_resolved_schematic_count audited_wire_count unaccounted_wire_networks_by_schematic

        @test schematic_count == length(schematic_paths)
        @test schematic_count > 0
        @test symbol_count > 0
        @test resolved_symbol_count > 0
        @test pin_count > 0
        @test Set(keys(orientation_counts)) ==
              Set(("R0", "R90", "R180", "R270", "M0", "M90", "M180", "M270"))
        @test match_rate >= INSTALLED_EXAMPLE_MINIMUM_PIN_WIRE_MATCH
        @test fully_resolved_schematic_count > 0
        @test audited_wire_count > 0
        @test isempty(unaccounted_wire_networks_by_schematic)

        for (orientation, orientation_match_rate) in orientation_match_rates
            @test orientation_match_rate >= INSTALLED_EXAMPLE_MINIMUM_PIN_WIRE_MATCH
        end
    end
end