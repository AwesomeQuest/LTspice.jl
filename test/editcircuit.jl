using LTspice
using Test

@testset "EditCircuit" begin
    complete_schematics = sort(filter(
        path -> occursin(r"^test(?:[1-9]|1[0-7]|Inc1)\.asc$", basename(path)),
        readdir(@__DIR__; join=true),
    ))

    @test !isempty(complete_schematics)

    for sourcepath in complete_schematics
        circuit = readcircuit(sourcepath)

        @test circuit.sourcepath == abspath(sourcepath)
        @test !isempty(circuit.records)
        @test startswith(first(circuit.records), "Version")

        mktemp() do outputpath, io
            close(io)
            writtenpath = writecircuit(outputpath, circuit)

            @test writtenpath == abspath(outputpath)
            @test read(outputpath) == read(sourcepath)
        end
    end

    sourcepath = joinpath(@__DIR__, "test1.asc")
    circuit = readcircuit(sourcepath)
    original = circuit[1]
    circuit[1] = "Version 4\n"

    @test circuit[1] == "Version 4\n"

    circuit[1] = original
    @test circuit[1] == original

    @test_throws ArgumentError readcircuit(joinpath(@__DIR__, "missing.asc"))

    @testset "get existing components and index pins" begin
        circuit = readcircuit(sourcepath)
        existing_components = components(circuit)

        @test length(existing_components) == 2
        @test existing_components[1] ==
              CircuitComponent("voltage", "V1", "{Vin}", (80, 96), "R0")
        @test existing_components[2] ==
              CircuitComponent("res", "R1", "{load}", (224, 96), "R0")
        @test component(circuit, "V1") == existing_components[1]
        @test component(circuit, "R1") == existing_components[2]
        @test component(circuit, "V1")[1] == CircuitPin(existing_components[1], 1)
        @test_throws KeyError component(circuit, "missing")
        @test_throws ArgumentError component(circuit, "V1")[0]
    end

    @testset "add components and connections" begin
        circuit = readcircuit(sourcepath)

        component = addcomponent!(
            circuit,
            "res",
            "R2",
            "10";
            position=(384, 96),
            orientation="R0",
        )
        addwire!(circuit, (240, 64), (400, 64))
        addwire!(circuit, (240, 192), (400, 192))
        addflag!(circuit, (400, 192), "0")
        adddirective!(
            circuit,
            ".MEASURE TRAN Current2 PARAM I(R2)";
            position=(304, 0),
        )

        @test component == CircuitComponent("res", "R2", "10", (384, 96), "R0")
        @test "SYMBOL res 384 96 R0\n" in circuit.records
        @test "SYMATTR InstName R2\n" in circuit.records
        @test "SYMATTR Value 10\n" in circuit.records
        @test "WIRE 240 64 400 64\n" in circuit.records
        @test "WIRE 240 192 400 192\n" in circuit.records
        @test "FLAG 400 192 0\n" in circuit.records
        @test "TEXT 304 0 Left 2 !.MEASURE TRAN Current2 PARAM I(R2)\n" in circuit.records

        @test_throws ArgumentError addcomponent!(
            circuit,
            "res",
            "R2",
            "20";
            position=(480, 96),
        )
        @test_throws ArgumentError addcomponent!(
            circuit,
            "res",
            "R3",
            "20";
            position=(480, 96),
            orientation="invalid",
        )
        @test_throws ArgumentError addwire!(circuit, (0, 0), (0, 0))

        @testset "connect component pins" begin
            connection_circuit = readcircuit(sourcepath)
            library = SymbolLibrary(schematic_path=sourcepath)
            first_component = addcomponent!(
                connection_circuit,
                "res",
                "R2",
                "10";
                position=(384, 96),
            )
            second_component = addcomponent!(
                connection_circuit,
                "res",
                "R3",
                "20";
                position=(480, 96),
                orientation="M0",
            )

            @test connect!(
                connection_circuit,
                first_component[1],
                second_component[1];
                library=library,
            ) === connection_circuit
            @test "WIRE 400 112 464 112\n" in connection_circuit.records

            @test connect!(
                connection_circuit,
                first_component[2],
                (448, 192);
                library=library,
            ) === connection_circuit
            @test "WIRE 400 192 448 192\n" in connection_circuit.records

            @test connect!(
                connection_circuit,
                (448, 192),
                second_component[2];
                library=library,
            ) === connection_circuit
            @test "WIRE 448 192 464 192\n" in connection_circuit.records

            @test_throws ArgumentError connect!(
                connection_circuit,
                first_component,
                3,
                second_component,
                1;
                library=library,
            )
            @test_throws ArgumentError connect!(
                connection_circuit,
                first_component,
                1,
                first_component,
                1;
                library=library,
            )
        end

        mktempdir() do directory
            outputpath = joinpath(directory, "generated.asc")
            writecircuit(outputpath, circuit)

            @test isfile(outputpath)
            @test readcircuit(outputpath).records == circuit.records

            parsed = LTspice.parsecircuitfile(outputpath, outputpath, "", [])
            @test "Current2" in parsed.measurementnames
        end
    end
end
