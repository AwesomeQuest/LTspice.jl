using LTspice
using Test

@testset "SymbolDefinitions" begin
    @testset "parse installed symbol automatically" begin
        library = SymbolLibrary()
        symbolpath = find_symbol_definition(library, "res")
        definition = load_symbol_definition(library, "res")

        @test isfile(symbolpath)
        @test basename(symbolpath) == "res.asy"
        @test definition.path == abspath(symbolpath)
        @test definition.name == "res"
        @test length(definition.pins) == 2
        @test definition.pins[1] == SymbolPin((16, 16), "A", 1)
        @test definition.pins[2] == SymbolPin((16, 96), "B", 2)
        @test load_symbol_definition(library, "RES") === definition
        @test pin_position(definition, 1, (384, 96)) == (400, 112)
        @test pin_position(definition, 2, (384, 96)) == (400, 192)
    end

    @testset "nested installed symbols" begin
        library = SymbolLibrary()
        symbolpath = find_symbol_definition(library, "ADC/AD4000")
        definition = load_symbol_definition(library, "adc/ad4000.asy")

        @test isfile(symbolpath)
        @test definition.name == "AD4000"
        @test length(definition.pins) == 6
        @test first(definition.pins).spice_order == 1
        @test last(definition.pins).spice_order == 9
    end

    @testset "search precedence" begin
        mktempdir() do directory
            schematic_directory = joinpath(directory, "schematic")
            custom_directory = joinpath(directory, "custom")
            executable_directory = joinpath(directory, "installation")
            executable_symbols = joinpath(executable_directory, "lib", "sym")

            mkpath(joinpath(schematic_directory, "lib", "sym"))
            mkpath(custom_directory)
            mkpath(executable_symbols)

            symboltext(position) = """
            Version 4
            SymbolType CELL
            PIN $(position[1]) $(position[2]) NONE 0
            PINATTR PinName P
            PINATTR SpiceOrder 1
            """

            write(
                joinpath(schematic_directory, "local.asy"),
                symboltext((1, 1)),
            )
            write(
                joinpath(schematic_directory, "lib", "sym", "shared.asy"),
                symboltext((2, 2)),
            )
            write(
                joinpath(custom_directory, "shared.asy"),
                symboltext((3, 3)),
            )
            write(
                joinpath(executable_symbols, "installed.asy"),
                symboltext((4, 4)),
            )

            executable = joinpath(executable_directory, "LTspice.exe")
            write(executable, "")

            paths = default_symbol_search_paths(
                schematic_path=joinpath(schematic_directory, "circuit.asc"),
                executable_path=executable,
                additional_paths=[custom_directory],
            )
            library = SymbolLibrary(paths)

            @test paths[1] == abspath(schematic_directory)
            @test paths[2] == abspath(joinpath(schematic_directory, "lib", "sym"))
            @test paths[3] == abspath(custom_directory)
            @test abspath(executable_symbols) in paths

            @test load_symbol_definition(library, "local").pins[1].position == (1, 1)
            @test load_symbol_definition(library, "shared").pins[1].position == (2, 2)
            @test load_symbol_definition(library, "installed").pins[1].position == (4, 4)
        end
    end

    @testset "Wine current and legacy locations" begin
        mktempdir() do prefix
            wine_user = joinpath(prefix, "drive_c", "users", "tester")
            current_symbols =
                joinpath(wine_user, "AppData", "Local", "LTspice", "lib", "sym")
            xvii_symbols =
                joinpath(wine_user, "Documents", "LTspiceXVII", "lib", "sym")
            iv_symbols =
                joinpath(wine_user, "Documents", "LTspiceIV", "lib", "sym")
            current_install = joinpath(
                prefix,
                "drive_c",
                "Program Files",
                "ADI",
                "LTspice",
                "lib",
                "sym",
            )
            xvii_install = joinpath(
                prefix,
                "drive_c",
                "Program Files",
                "LTC",
                "LTspiceXVII",
                "lib",
                "sym",
            )
            iv_install = joinpath(
                prefix,
                "drive_c",
                "Program Files (x86)",
                "LTC",
                "LTspiceIV",
                "lib",
                "sym",
            )

            for path in (
                current_symbols,
                xvii_symbols,
                iv_symbols,
                current_install,
                xvii_install,
                iv_install,
            )
                mkpath(path)
            end

            withenv("WINEPREFIX" => prefix) do
                paths = default_symbol_search_paths(
                    executable_path=joinpath(
                        prefix,
                        "drive_c",
                        "Program Files",
                        "ADI",
                        "LTspice",
                        "LTspice.exe",
                    ),
                )

                @test abspath(current_symbols) in paths
                @test abspath(xvii_symbols) in paths
                @test abspath(iv_symbols) in paths
                @test abspath(current_install) in paths
                @test abspath(xvii_install) in paths
                @test abspath(iv_install) in paths
            end
        end
    end

    @testset "orientation transforms" begin
        definition = SymbolDefinition(
            "test",
            "test.asy",
            [SymbolPin((16, 32), "P", 1)],
        )
        origin = (100, 200)

        @test pin_position(definition, 1, origin, "R0") == (116, 232)
        @test pin_position(definition, 1, origin, "R90") == (68, 216)
        @test pin_position(definition, 1, origin, "R180") == (84, 168)
        @test pin_position(definition, 1, origin, "R270") == (132, 184)
        @test pin_position(definition, 1, origin, "M0") == (84, 232)
        @test pin_position(definition, 1, origin, "M90") == (132, 216)
        @test pin_position(definition, 1, origin, "M180") == (116, 168)
        @test pin_position(definition, 1, origin, "M270") == (68, 184)
        @test_throws ArgumentError pin_position(definition, 2, origin)
        @test_throws ArgumentError pin_position(definition, 1, origin, "invalid")
    end

    @testset "invalid definitions and missing symbols" begin
        mktempdir() do directory
            missing_order = joinpath(directory, "missing_order.asy")
            duplicate_order = joinpath(directory, "duplicate_order.asy")
            no_pins = joinpath(directory, "no_pins.asy")

            write(missing_order, "Version 4\nPIN 0 0 NONE 0\n")
            write(
                duplicate_order,
                """
                Version 4
                PIN 0 0 NONE 0
                PINATTR SpiceOrder 1
                PIN 16 0 NONE 0
                PINATTR SpiceOrder 1
                """,
            )
            write(no_pins, "Version 4\nSymbolType CELL\n")

            @test_throws ArgumentError read_symbol_definition(missing_order)
            @test_throws ArgumentError read_symbol_definition(duplicate_order)
            @test_throws ArgumentError read_symbol_definition(no_pins)
            @test_throws ArgumentError find_symbol_definition(
                SymbolLibrary([directory]),
                "does-not-exist",
            )
        end
    end
end