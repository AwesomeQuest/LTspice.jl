export CircuitWire, CircuitFlag, CircuitNet, CircuitTopology, CircuitGraph
export circuit_topology, net, disconnected_pins, floating_wire_networks
export electrical_graph, graph, circuit_object, circuit_vertex, edge_pins, edge_nets

"""A wire segment parsed from an LTspice schematic."""
struct CircuitWire
    from::NTuple{2,Int}
    to::NTuple{2,Int}
end

"""A named electrical anchor parsed from a `FLAG` or `IOPIN` record."""
struct CircuitFlag
    position::NTuple{2,Int}
    name::String
    kind::Symbol
end

"""
An electrical net in an LTspice schematic.

`names` contains labels assigned with `FLAG` records. Ground is represented by
the name `"0"`. Separate wire networks carrying the same name are merged.
"""
struct CircuitNet
    id::Int
    names::Vector{String}
    pins::Vector{CircuitPin}
    wires::Vector{CircuitWire}
    flags::Vector{CircuitFlag}
end

"""
The electrical topology derived from an LTspice schematic.

`nets` contains connected electrical networks, `disconnected_pins` contains
symbol pins with no wire or flag connection, and `floating_wire_networks`
contains wire groups touching neither a symbol pin nor a net anchor.
"""
struct CircuitTopology
    components::Vector{CircuitComponent}
    nets::Vector{CircuitNet}
    disconnected_pins::Vector{CircuitPin}
    floating_wire_networks::Vector{Vector{CircuitWire}}
end

"""
A Graphs.jl representation of a circuit topology.

`graph` is the underlying Graphs.jl graph. `representation` is either
`:bipartite` or `:components`. Use `circuit_object`, `circuit_vertex`,
`edge_pins`, and `edge_nets` to move between graph indices and circuit objects.
"""
struct CircuitGraph{G}
    graph::G
    representation::Symbol
    vertex_objects::Vector{Union{CircuitComponent,CircuitNet}}
    object_vertices::Dict{Any,Int}
    edge_pin_map::Dict{Tuple{Int,Int},Vector{CircuitPin}}
    edge_net_map::Dict{Tuple{Int,Int},Vector{CircuitNet}}
end

disconnected_pins(topology::CircuitTopology) = topology.disconnected_pins
floating_wire_networks(topology::CircuitTopology) = topology.floating_wire_networks

"""
    electrical_graph(topology; representation=:bipartite)

Construct a Graphs.jl representation of a circuit topology. This method is
provided by the optional Graphs.jl extension and becomes available after
loading Graphs.

Supported representations are:

- `:bipartite`: component and net vertices, with component-pin attachments as
  edges.
- `:components`: component vertices connected when they share an electrical
  net.
"""
function electrical_graph end

"""Return the underlying Graphs.jl graph."""
graph(circuit_graph::CircuitGraph) = circuit_graph.graph

"""Return the circuit component or net represented by a graph vertex."""
function circuit_object(graph::CircuitGraph, vertex::Integer)
    1 <= vertex <= length(graph.vertex_objects) || throw(BoundsError(graph, vertex))
    return graph.vertex_objects[Int(vertex)]
end

"""Return the graph vertex representing a circuit component or net."""
function circuit_vertex(graph::CircuitGraph, object)
    vertex = get(graph.object_vertices, object, nothing)
    vertex === nothing && throw(KeyError(object))
    return vertex
end

_circuit_edge_key(from::Integer, to::Integer) =
    from <= to ? (Int(from), Int(to)) : (Int(to), Int(from))

"""Return the component pins represented by a graph edge."""
function edge_pins(graph::CircuitGraph, from::Integer, to::Integer)
    return get(graph.edge_pin_map, _circuit_edge_key(from, to), CircuitPin[])
end

"""Return the electrical nets represented by a component-graph edge."""
function edge_nets(graph::CircuitGraph, from::Integer, to::Integer)
    return get(graph.edge_net_map, _circuit_edge_key(from, to), CircuitNet[])
end

function _topology_point_on_wire(point, wire::CircuitWire)
    x, y = point
    x1, y1 = wire.from
    x2, y2 = wire.to

    (x - x1) * (y2 - y1) == (y - y1) * (x2 - x1) || return false
    return min(x1, x2) <= x <= max(x1, x2) &&
           min(y1, y2) <= y <= max(y1, y2)
end

function _topology_wires_intersect(first::CircuitWire, second::CircuitWire)
    function orientation(first_point, second_point, third_point)
        value =
            (second_point[1] - first_point[1]) *
            (third_point[2] - first_point[2]) -
            (second_point[2] - first_point[2]) *
            (third_point[1] - first_point[1])
        return sign(value)
    end

    first_from_orientation = orientation(first.from, first.to, second.from)
    first_to_orientation = orientation(first.from, first.to, second.to)
    second_from_orientation = orientation(second.from, second.to, first.from)
    second_to_orientation = orientation(second.from, second.to, first.to)

    first_from_orientation != first_to_orientation &&
        second_from_orientation != second_to_orientation && return true

    first_from_orientation == 0 && _topology_point_on_wire(second.from, first) && return true
    first_to_orientation == 0 && _topology_point_on_wire(second.to, first) && return true
    second_from_orientation == 0 && _topology_point_on_wire(first.from, second) && return true
    return second_to_orientation == 0 && _topology_point_on_wire(first.to, second)
end

function _parse_topology_records(circuit::CircuitDocument)
    wires = CircuitWire[]
    flags = CircuitFlag[]

    for record in circuit.records
        fields = split(strip(record))
        isempty(fields) && continue

        if fields[1] == "WIRE"
            length(fields) >= 5 ||
                throw(ArgumentError("malformed WIRE record: $record"))
            push!(
                wires,
                CircuitWire(
                    (parse(Int, fields[2]), parse(Int, fields[3])),
                    (parse(Int, fields[4]), parse(Int, fields[5])),
                ),
            )
        elseif fields[1] == "FLAG"
            length(fields) >= 4 ||
                throw(ArgumentError("malformed FLAG record: $record"))
            push!(
                flags,
                CircuitFlag(
                    (parse(Int, fields[2]), parse(Int, fields[3])),
                    join(fields[4:end], " "),
                    :flag,
                ),
            )
        elseif fields[1] == "IOPIN"
            length(fields) >= 4 ||
                throw(ArgumentError("malformed IOPIN record: $record"))
            push!(
                flags,
                CircuitFlag(
                    (parse(Int, fields[2]), parse(Int, fields[3])),
                    join(fields[4:end], " "),
                    :iopin,
                ),
            )
        end
    end

    return wires, flags
end

function _topology_pin_positions(
    circuit::CircuitDocument,
    circuit_components,
    library::SymbolLibrary,
)
    pins = CircuitPin[]
    positions = NTuple{2,Int}[]

    for circuit_component in circuit_components
        definition = load_symbol_definition(library, circuit_component.symbol)
        for symbol_pin in definition.pins
            push!(pins, circuit_component[symbol_pin.spice_order])
            push!(
                positions,
                pin_position(
                    definition,
                    symbol_pin.spice_order,
                    circuit_component.position,
                    circuit_component.orientation,
                ),
            )
        end
    end

    return pins, positions
end

"""
    circuit_topology(circuit; library=nothing) -> CircuitTopology

Construct electrical topology from schematic components, symbol definitions,
wires, `FLAG` records, and `IOPIN` records.

Wire segments are connected when they intersect, including T-junctions and
crossings. Pins and net anchors connect when they lie anywhere on a wire.
Separate wire groups with the same `FLAG` name are merged, including the global
ground net `"0"`. `DATAFLAG` records are display annotations and are ignored.
"""
function circuit_topology(
    circuit::CircuitDocument;
    library::Union{Nothing,SymbolLibrary}=nothing,
)
    symbol_library = library === nothing ?
        SymbolLibrary(schematic_path=circuit.sourcepath) : library

    circuit_components = components(circuit)
    wires, flags = _parse_topology_records(circuit)
    pins, pin_positions =
        _topology_pin_positions(circuit, circuit_components, symbol_library)

    wire_count = length(wires)
    pin_count = length(pins)
    flag_count = length(flags)
    node_count = wire_count + pin_count + flag_count
    parent = collect(1:node_count)

    function find_root(index)
        while parent[index] != index
            parent[index] = parent[parent[index]]
            index = parent[index]
        end
        return index
    end

    function union_nodes!(first, second)
        first_root = find_root(first)
        second_root = find_root(second)
        first_root == second_root || (parent[second_root] = first_root)
    end

    for first_index in eachindex(wires)
        for second_index in (first_index + 1):wire_count
            _topology_wires_intersect(wires[first_index], wires[second_index]) &&
                union_nodes!(first_index, second_index)
        end
    end

    for pin_index in eachindex(pins)
        pin_node = wire_count + pin_index
        position = pin_positions[pin_index]
        for wire_index in eachindex(wires)
            _topology_point_on_wire(position, wires[wire_index]) &&
                union_nodes!(pin_node, wire_index)
        end
    end

    for flag_index in eachindex(flags)
        flag_node = wire_count + pin_count + flag_index
        position = flags[flag_index].position
        for wire_index in eachindex(wires)
            _topology_point_on_wire(position, wires[wire_index]) &&
                union_nodes!(flag_node, wire_index)
        end
    end

    coordinate_nodes = Dict{NTuple{2,Int},Int}()
    for pin_index in eachindex(pins)
        node = wire_count + pin_index
        position = pin_positions[pin_index]
        haskey(coordinate_nodes, position) ?
            union_nodes!(node, coordinate_nodes[position]) :
            (coordinate_nodes[position] = node)
    end
    for flag_index in eachindex(flags)
        node = wire_count + pin_count + flag_index
        position = flags[flag_index].position
        haskey(coordinate_nodes, position) ?
            union_nodes!(node, coordinate_nodes[position]) :
            (coordinate_nodes[position] = node)
    end

    named_flag_nodes = Dict{String,Int}()
    for flag_index in eachindex(flags)
        flags[flag_index].kind == :flag || continue
        node = wire_count + pin_count + flag_index
        name = flags[flag_index].name
        haskey(named_flag_nodes, name) ?
            union_nodes!(node, named_flag_nodes[name]) :
            (named_flag_nodes[name] = node)
    end

    groups = Dict{Int,Vector{Int}}()
    for node in 1:node_count
        push!(get!(groups, find_root(node), Int[]), node)
    end

    nets = CircuitNet[]
    disconnected = CircuitPin[]
    floating = Vector{Vector{CircuitWire}}()

    for nodes in values(groups)
        wire_indices = filter(node -> node <= wire_count, nodes)
        pin_indices = [
            node - wire_count
            for node in nodes
            if wire_count < node <= wire_count + pin_count
        ]
        flag_indices = [
            node - wire_count - pin_count
            for node in nodes
            if node > wire_count + pin_count
        ]

        if isempty(wire_indices) && isempty(flag_indices)
            append!(disconnected, pins[pin_indices])
            continue
        end

        net_wires = wires[wire_indices]
        net_pins = pins[pin_indices]
        net_flags = flags[flag_indices]
        names = sort!(unique(
            flag.name for flag in net_flags if flag.kind == :flag
        ))

        if !isempty(net_wires) && isempty(net_pins) && isempty(net_flags)
            push!(floating, net_wires)
        end

        push!(
            nets,
            CircuitNet(
                length(nets) + 1,
                names,
                net_pins,
                net_wires,
                net_flags,
            ),
        )
    end

    sort!(nets; by=item -> item.id)
    sort!(disconnected; by=item -> (item.component.instance, item.spice_order))
    return CircuitTopology(circuit_components, nets, disconnected, floating)
end

"""
    net(topology, name) -> CircuitNet

Return the unique electrical net carrying `name`. Use `"0"` for ground.
"""
function net(topology::CircuitTopology, name::AbstractString)
    matches = filter(item -> String(name) in item.names, topology.nets)
    isempty(matches) && throw(KeyError(name))
    length(matches) == 1 ||
        throw(ArgumentError("net name is not unique: $name"))
    return only(matches)
end

"""
    net(topology, pin::CircuitPin) -> CircuitNet

Return the electrical net connected to an indexed component pin.
"""
function net(topology::CircuitTopology, pin::CircuitPin)
    matches = filter(item -> pin in item.pins, topology.nets)
    isempty(matches) && throw(KeyError(pin))
    length(matches) == 1 ||
        throw(ArgumentError("pin belongs to more than one net"))
    return only(matches)
end