module LTspiceGraphsExt

using LTspice
import Graphs

function _add_circuit_edge!(
    graph,
    edge_pin_map,
    edge_net_map,
    from::Integer,
    to::Integer,
    pins,
    nets,
)
    from == to && return
    key = LTspice._circuit_edge_key(from, to)
    Graphs.add_edge!(graph, from, to)
    append!(get!(edge_pin_map, key, LTspice.CircuitPin[]), pins)
    append!(get!(edge_net_map, key, LTspice.CircuitNet[]), nets)
    unique!(edge_pin_map[key])
    unique!(edge_net_map[key])
    return
end

function _bipartite_graph(topology::LTspice.CircuitTopology)
    vertex_objects = Union{LTspice.CircuitComponent,LTspice.CircuitNet}[
        topology.components...
        topology.nets...
    ]
    object_vertices = Dict{Any,Int}(
        object => index for (index, object) in pairs(vertex_objects)
    )
    graph = Graphs.SimpleGraph(length(vertex_objects))
    edge_pin_map = Dict{Tuple{Int,Int},Vector{LTspice.CircuitPin}}()
    edge_net_map = Dict{Tuple{Int,Int},Vector{LTspice.CircuitNet}}()

    for circuit_net in topology.nets
        net_vertex = object_vertices[circuit_net]
        pins_by_component =
            Dict{LTspice.CircuitComponent,Vector{LTspice.CircuitPin}}()

        for pin in circuit_net.pins
            push!(
                get!(
                    pins_by_component,
                    pin.component,
                    LTspice.CircuitPin[],
                ),
                pin,
            )
        end

        for (component, pins) in pins_by_component
            component_vertex = object_vertices[component]
            _add_circuit_edge!(
                graph,
                edge_pin_map,
                edge_net_map,
                component_vertex,
                net_vertex,
                pins,
                [circuit_net],
            )
        end
    end

    return LTspice.CircuitGraph(
        graph,
        :bipartite,
        vertex_objects,
        object_vertices,
        edge_pin_map,
        edge_net_map,
    )
end

function _component_graph(topology::LTspice.CircuitTopology)
    vertex_objects = Union{LTspice.CircuitComponent,LTspice.CircuitNet}[
        topology.components...
    ]
    object_vertices = Dict{Any,Int}(
        object => index for (index, object) in pairs(vertex_objects)
    )
    graph = Graphs.SimpleGraph(length(vertex_objects))
    edge_pin_map = Dict{Tuple{Int,Int},Vector{LTspice.CircuitPin}}()
    edge_net_map = Dict{Tuple{Int,Int},Vector{LTspice.CircuitNet}}()

    for circuit_net in topology.nets
        pins_by_component =
            Dict{LTspice.CircuitComponent,Vector{LTspice.CircuitPin}}()

        for pin in circuit_net.pins
            push!(
                get!(
                    pins_by_component,
                    pin.component,
                    LTspice.CircuitPin[],
                ),
                pin,
            )
        end

        connected_components = collect(keys(pins_by_component))
        for first_index in eachindex(connected_components)
            for second_index in (first_index + 1):length(connected_components)
                first_component = connected_components[first_index]
                second_component = connected_components[second_index]
                pins = vcat(
                    pins_by_component[first_component],
                    pins_by_component[second_component],
                )
                _add_circuit_edge!(
                    graph,
                    edge_pin_map,
                    edge_net_map,
                    object_vertices[first_component],
                    object_vertices[second_component],
                    pins,
                    [circuit_net],
                )
            end
        end
    end

    return LTspice.CircuitGraph(
        graph,
        :components,
        vertex_objects,
        object_vertices,
        edge_pin_map,
        edge_net_map,
    )
end

function LTspice.electrical_graph(
    topology::LTspice.CircuitTopology;
    representation::Symbol=:bipartite,
)
    representation == :bipartite && return _bipartite_graph(topology)
    representation == :components && return _component_graph(topology)
    throw(ArgumentError(
        "unsupported electrical graph representation: $representation",
    ))
end

function LTspice.electrical_graph(
    circuit::LTspice.CircuitDocument;
    representation::Symbol=:bipartite,
    library::Union{Nothing,LTspice.SymbolLibrary}=nothing,
)
    topology = LTspice.circuit_topology(circuit; library=library)
    return LTspice.electrical_graph(
        topology;
        representation=representation,
    )
end

Graphs.nv(graph::LTspice.CircuitGraph) = Graphs.nv(graph.graph)
Graphs.ne(graph::LTspice.CircuitGraph) = Graphs.ne(graph.graph)
Graphs.vertices(graph::LTspice.CircuitGraph) = Graphs.vertices(graph.graph)
Graphs.edges(graph::LTspice.CircuitGraph) = Graphs.edges(graph.graph)
Graphs.has_vertex(graph::LTspice.CircuitGraph, vertex) =
    Graphs.has_vertex(graph.graph, vertex)
Graphs.has_edge(graph::LTspice.CircuitGraph, from, to) =
    Graphs.has_edge(graph.graph, from, to)
Graphs.neighbors(graph::LTspice.CircuitGraph, vertex) =
    Graphs.neighbors(graph.graph, vertex)
Graphs.degree(graph::LTspice.CircuitGraph, vertex) =
    Graphs.degree(graph.graph, vertex)

LTspice.edge_pins(graph::LTspice.CircuitGraph, edge::Graphs.AbstractEdge) =
    LTspice.edge_pins(graph, Graphs.src(edge), Graphs.dst(edge))

LTspice.edge_nets(graph::LTspice.CircuitGraph, edge::Graphs.AbstractEdge) =
    LTspice.edge_nets(graph, Graphs.src(edge), Graphs.dst(edge))

end