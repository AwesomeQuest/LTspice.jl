using LTspice
using Test

@testset "CircuitTopology" begin
    @testset "topology from existing schematic" begin
        circuit = readcircuit(joinpath(@__DIR__, "test1.asc"))
        topology = circuit_topology(circuit)

        source = component(circuit, "V1")
        resistor = component(circuit, "R1")

        @test length(topology.components) == 2
        @test isempty(floating_wire_networks(topology))
        @test isempty(disconnected_pins(topology))

        source_positive_net = net(topology, source[1])
        source_negative_net = net(topology, source[2])
        resistor_positive_net = net(topology, resistor[1])
        resistor_negative_net = net(topology, resistor[2])

        @test source_positive_net === resistor_positive_net
        @test source_negative_net === resistor_negative_net
        @test source_negative_net === net(topology, "0")
        @test Set(source_positive_net.pins) == Set((source[1], resistor[1]))
        @test Set(source_negative_net.pins) == Set((source[2], resistor[2]))
        @test length(net(topology, "0").flags) == 2
    end

    @testset "named flags merge separate wire networks" begin
        circuit = CircuitDocument([
            "Version 4\n",
            "SHEET 1 880 680\n",
            "WIRE 0 0 32 0\n",
            "WIRE 128 0 160 0\n",
            "FLAG 0 0 SIGNAL\n",
            "FLAG 160 0 SIGNAL\n",
        ])

        topology = circuit_topology(
            circuit;
            library=SymbolLibrary(String[]),
        )
        signal = net(topology, "SIGNAL")

        @test length(topology.nets) == 1
        @test length(signal.wires) == 2
        @test length(signal.flags) == 2
        @test isempty(disconnected_pins(topology))
        @test isempty(floating_wire_networks(topology))
    end

    @testset "direct pin flags and disconnected pins" begin
        mktempdir() do directory
            write(
                joinpath(directory, "onepin.asy"),
                """
                Version 4
                SymbolType CELL
                PIN 16 0 NONE 0
                PINATTR PinName P
                PINATTR SpiceOrder 1
                """,
            )

            circuit = CircuitDocument(
                [
                    "Version 4\n",
                    "SHEET 1 880 680\n",
                    "FLAG 16 0 DIRECT\n",
                    "SYMBOL onepin 0 0 R0\n",
                    "SYMATTR InstName X1\n",
                    "SYMATTR Value onepin\n",
                    "SYMBOL onepin 64 0 R0\n",
                    "SYMATTR InstName X2\n",
                    "SYMATTR Value onepin\n",
                ];
                sourcepath=joinpath(directory, "circuit.asc"),
            )
            topology = circuit_topology(
                circuit;
                library=SymbolLibrary([directory]),
            )

            first_component = component(circuit, "X1")
            second_component = component(circuit, "X2")

            @test net(topology, first_component[1]) === net(topology, "DIRECT")
            @test disconnected_pins(topology) == [second_component[1]]
            @test_throws KeyError net(topology, second_component[1])
        end
    end

    @testset "T-junctions and floating wire networks" begin
        circuit = CircuitDocument([
            "Version 4\n",
            "SHEET 1 880 680\n",
            "WIRE 0 0 64 0\n",
            "WIRE 32 0 32 32\n",
            "FLAG 32 32 CONNECTED\n",
            "WIRE 128 0 160 0\n",
        ])
        topology = circuit_topology(
            circuit;
            library=SymbolLibrary(String[]),
        )

        connected = net(topology, "CONNECTED")
        floating = floating_wire_networks(topology)

        @test length(connected.wires) == 2
        @test length(floating) == 1
        @test floating[1] == [CircuitWire((128, 0), (160, 0))]
    end

    @testset "crossing wires form one LTspice network" begin
        circuit = CircuitDocument([
            "Version 4\n",
            "SHEET 1 880 680\n",
            "WIRE 0 16 32 16\n",
            "WIRE 16 0 16 32\n",
            "FLAG 0 16 CROSSING\n",
        ])
        topology = circuit_topology(
            circuit;
            library=SymbolLibrary(String[]),
        )

        @test length(net(topology, "CROSSING").wires) == 2
        @test isempty(floating_wire_networks(topology))
    end
end