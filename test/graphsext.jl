using LTspice
using Graphs
using Test

@testset "Graphs extension" begin
    circuit = readcircuit(joinpath(@__DIR__, "test1.asc"))
    topology = circuit_topology(circuit)
    source = component(circuit, "V1")
    resistor = component(circuit, "R1")

    @test Base.get_extension(LTspice, :LTspiceGraphsExt) !== nothing

    @testset "bipartite component-net graph" begin
        circuit_graph = electrical_graph(topology)
        underlying_graph = graph(circuit_graph)

        @test circuit_graph.representation == :bipartite
        @test nv(circuit_graph) == 4
        @test ne(circuit_graph) == 4
        @test nv(underlying_graph) == 4
        @test ne(underlying_graph) == 4
        @test length(connected_components(underlying_graph)) == 1

        source_vertex = circuit_vertex(circuit_graph, source)
        resistor_vertex = circuit_vertex(circuit_graph, resistor)
        positive_net = net(topology, source[1])
        ground_net = net(topology, "0")
        positive_vertex = circuit_vertex(circuit_graph, positive_net)
        ground_vertex = circuit_vertex(circuit_graph, ground_net)

        @test circuit_object(circuit_graph, source_vertex) == source
        @test circuit_object(circuit_graph, resistor_vertex) == resistor
        @test circuit_object(circuit_graph, positive_vertex) === positive_net
        @test circuit_object(circuit_graph, ground_vertex) === ground_net

        @test has_edge(circuit_graph, source_vertex, positive_vertex)
        @test has_edge(circuit_graph, source_vertex, ground_vertex)
        @test has_edge(circuit_graph, resistor_vertex, positive_vertex)
        @test has_edge(circuit_graph, resistor_vertex, ground_vertex)
        @test !has_edge(circuit_graph, source_vertex, resistor_vertex)

        @test edge_pins(circuit_graph, source_vertex, positive_vertex) ==
              [source[1]]
        @test edge_pins(circuit_graph, positive_vertex, resistor_vertex) ==
              [resistor[1]]
        @test edge_nets(circuit_graph, source_vertex, positive_vertex) ==
              [positive_net]

        first_edge = first(edges(circuit_graph))
        @test !isempty(edge_pins(circuit_graph, first_edge))
        @test length(edge_nets(circuit_graph, first_edge)) == 1
    end

    @testset "component projection" begin
        circuit_graph =
            electrical_graph(topology; representation=:components)
        underlying_graph = graph(circuit_graph)

        @test circuit_graph.representation == :components
        @test nv(circuit_graph) == 2
        @test ne(circuit_graph) == 1
        @test is_connected(underlying_graph)

        source_vertex = circuit_vertex(circuit_graph, source)
        resistor_vertex = circuit_vertex(circuit_graph, resistor)
        shared_nets = edge_nets(
            circuit_graph,
            source_vertex,
            resistor_vertex,
        )
        shared_pins = edge_pins(
            circuit_graph,
            source_vertex,
            resistor_vertex,
        )

        @test Set(shared_nets) ==
              Set((net(topology, source[1]), net(topology, source[2])))
        @test Set(shared_pins) ==
              Set((source[1], source[2], resistor[1], resistor[2]))
        @test circuit_object(circuit_graph, source_vertex) == source
        @test_throws KeyError circuit_vertex(
            circuit_graph,
            net(topology, "0"),
        )
    end

    @testset "construct directly from circuit" begin
        circuit_graph =
            electrical_graph(circuit; representation=:components)

        @test nv(circuit_graph) == 2
        @test ne(circuit_graph) == 1
    end

    @test_throws ArgumentError electrical_graph(
        topology;
        representation=:unsupported,
    )
    @test_throws BoundsError circuit_object(
        electrical_graph(topology),
        100,
    )
end