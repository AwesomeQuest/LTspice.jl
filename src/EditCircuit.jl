export CircuitDocument, CircuitComponent, CircuitPin
export readcircuit, writecircuit, components, component
export addcomponent!, addwire!, connect!, addflag!, adddirective!

"""
    CircuitDocument

A lossless, editable representation of an LTspice schematic file.

`records` contains each decoded source line, including its original line ending.
Unknown LTspice record types are preserved unchanged.
"""
mutable struct CircuitDocument
    records::Vector{String}
    encoding::StringEncodings.Encodings.Encoding
    sourcepath::Union{Nothing,String}
end

CircuitDocument(
    records::Vector{String};
    encoding=enc"windows-1252",
    sourcepath=nothing,
) = CircuitDocument(records, encoding, sourcepath)

"""A component added to an LTspice schematic document."""
struct CircuitComponent
    symbol::String
    instance::String
    value::String
    position::NTuple{2,Int}
    orientation::String
end

"""A pin reference created by indexing a `CircuitComponent`."""
struct CircuitPin
    component::CircuitComponent
    spice_order::Int
end

function Base.getindex(component::CircuitComponent, pin::Integer)
    pin > 0 || throw(ArgumentError("pin SpiceOrder must be positive"))
    return CircuitPin(component, Int(pin))
end

const LTSPICE_ORIENTATIONS = Set([
    "R0", "R90", "R180", "R270",
    "M0", "M90", "M180", "M270",
])

_circuit_newline(circuit::CircuitDocument) =
    any(endswith(record, "\r\n") for record in circuit.records) ? "\r\n" : "\n"

function _validate_record_value(value::AbstractString, description::AbstractString)
    isempty(value) && throw(ArgumentError("$description cannot be empty"))
    (occursin('\n', value) || occursin('\r', value)) &&
        throw(ArgumentError("$description cannot contain a newline"))
    return String(value)
end

function _insert_before_prefix!(
    circuit::CircuitDocument,
    records::Vector{String},
    prefixes::Tuple,
)
    index = findfirst(record -> any(startswith(record, prefix) for prefix in prefixes),
                      circuit.records)
    index === nothing ? append!(circuit.records, records) :
                        splice!(circuit.records, index:index-1, records)
    return circuit
end

"""
    addcomponent!(circuit, symbol, instance, value; position, orientation="R0")

Add an LTspice symbol and its instance-name and value attributes. The position
is expressed in LTspice schematic coordinates.
"""
function addcomponent!(
    circuit::CircuitDocument,
    symbol::AbstractString,
    instance::AbstractString,
    value::AbstractString;
    position::Tuple{<:Integer,<:Integer},
    orientation::Union{Symbol,AbstractString}="R0",
)
    symbol_name = _validate_record_value(symbol, "symbol name")
    instance_name = _validate_record_value(instance, "instance name")
    component_value = _validate_record_value(value, "component value")
    any(isspace, symbol_name) && throw(ArgumentError("symbol name cannot contain whitespace"))
    any(isspace, instance_name) && throw(ArgumentError("instance name cannot contain whitespace"))

    duplicate = any(circuit.records) do record
        startswith(record, "SYMATTR InstName ") &&
            strip(record[length("SYMATTR InstName ") + 1:end]) == instance_name
    end
    duplicate && throw(ArgumentError("component instance already exists: $instance_name"))

    orientation_name = string(orientation)
    orientation_name in LTSPICE_ORIENTATIONS ||
        throw(ArgumentError("unsupported LTspice orientation: $orientation_name"))

    x, y = Int.(position)
    newline = _circuit_newline(circuit)
    records = [
        "SYMBOL $symbol_name $x $y $orientation_name$newline",
        "SYMATTR InstName $instance_name$newline",
        "SYMATTR Value $component_value$newline",
    ]
    _insert_before_prefix!(circuit, records, ("TEXT ",))

    return CircuitComponent(
        symbol_name,
        instance_name,
        component_value,
        (x, y),
        orientation_name,
    )
end

"""Add a straight LTspice wire segment between two schematic coordinates."""
function addwire!(
    circuit::CircuitDocument,
    from::Tuple{<:Integer,<:Integer},
    to::Tuple{<:Integer,<:Integer},
)
    from == to && throw(ArgumentError("wire endpoints must be different"))
    x1, y1 = Int.(from)
    x2, y2 = Int.(to)
    record = "WIRE $x1 $y1 $x2 $y2$(_circuit_newline(circuit))"
    _insert_before_prefix!(circuit, [record], ("FLAG ", "SYMBOL ", "TEXT "))
    return circuit
end

"""
    components(circuit) -> Vector{CircuitComponent}

Return handles for all components already present in an LTspice schematic.
Each `SYMBOL` record is associated with its following `SYMATTR InstName` and
optional `SYMATTR Value` records.
"""
function components(circuit::CircuitDocument)
    result = CircuitComponent[]
    pending_symbol = nothing
    pending_instance = nothing
    pending_value = ""

    function finish_pending!()
        pending_symbol === nothing && return
        pending_instance === nothing &&
            throw(ArgumentError("SYMBOL record is missing SYMATTR InstName"))
        symbol, position, orientation = pending_symbol
        push!(
            result,
            CircuitComponent(symbol, pending_instance, pending_value, position, orientation),
        )
    end

    for record in circuit.records
        fields = split(strip(record))
        isempty(fields) && continue

        if fields[1] == "SYMBOL"
            length(fields) >= 5 || throw(ArgumentError("malformed SYMBOL record: $record"))
            finish_pending!()
            pending_symbol = (
                fields[2],
                (parse(Int, fields[3]), parse(Int, fields[4])),
                fields[5],
            )
            pending_instance = nothing
            pending_value = ""
        elseif pending_symbol !== nothing && fields[1] == "SYMATTR"
            length(fields) >= 3 || continue
            attribute = fields[2]
            value = join(fields[3:end], " ")
            attribute == "InstName" && (pending_instance = value)
            attribute == "Value" && (pending_value = value)
        end
    end

    finish_pending!()
    return result
end

"""
    component(circuit, instance) -> CircuitComponent

Return the unique component whose `InstName` equals `instance`.
"""
function component(circuit::CircuitDocument, instance::AbstractString)
    matches = filter(item -> item.instance == instance, components(circuit))
    isempty(matches) && throw(KeyError(instance))
    length(matches) == 1 ||
        throw(ArgumentError("component instance is not unique: $instance"))
    return only(matches)
end

function _component_pin_position(
    circuit::CircuitDocument,
    component::CircuitComponent,
    pin::Integer,
    library::Union{Nothing,SymbolLibrary},
)
    symbol_library = if library === nothing
        SymbolLibrary(schematic_path=circuit.sourcepath)
    else
        library
    end
    definition = load_symbol_definition(symbol_library, component.symbol)
    return pin_position(
        definition,
        pin,
        component.position,
        component.orientation,
    )
end

"""
    connect!(circuit, from_component, from_pin, to_component, to_pin;
             library=nothing)

Connect two component pins with a straight LTspice wire. Pin numbers are the
`SpiceOrder` values declared by each component's `.asy` symbol definition.

By default, symbol definitions are resolved relative to the circuit source and
the installed LTspice library. Pass a `SymbolLibrary` with `library` to use
custom search paths.
"""
function connect!(
    circuit::CircuitDocument,
    from_component::CircuitComponent,
    from_pin::Integer,
    to_component::CircuitComponent,
    to_pin::Integer;
    library::Union{Nothing,SymbolLibrary}=nothing,
)
    from = _component_pin_position(circuit, from_component, from_pin, library)
    to = _component_pin_position(circuit, to_component, to_pin, library)
    addwire!(circuit, from, to)
    return circuit
end

"""
    connect!(circuit, component, pin, point; library=nothing)
    connect!(circuit, point, component, pin; library=nothing)

Connect a component pin to an explicit schematic coordinate.
"""
function connect!(
    circuit::CircuitDocument,
    component::CircuitComponent,
    pin::Integer,
    point::Tuple{<:Integer,<:Integer};
    library::Union{Nothing,SymbolLibrary}=nothing,
)
    from = _component_pin_position(circuit, component, pin, library)
    addwire!(circuit, from, point)
    return circuit
end

function connect!(
    circuit::CircuitDocument,
    point::Tuple{<:Integer,<:Integer},
    component::CircuitComponent,
    pin::Integer;
    library::Union{Nothing,SymbolLibrary}=nothing,
)
    to = _component_pin_position(circuit, component, pin, library)
    addwire!(circuit, point, to)
    return circuit
end

"""
    connect!(circuit, from::CircuitPin, to::CircuitPin; library=nothing)

Connect indexed component-pin handles, for example
`connect!(circuit, source[1], resistor[1])`.
"""
function connect!(
    circuit::CircuitDocument,
    from::CircuitPin,
    to::CircuitPin;
    library::Union{Nothing,SymbolLibrary}=nothing,
)
    return connect!(
        circuit,
        from.component,
        from.spice_order,
        to.component,
        to.spice_order;
        library=library,
    )
end

function connect!(
    circuit::CircuitDocument,
    pin::CircuitPin,
    point::Tuple{<:Integer,<:Integer};
    library::Union{Nothing,SymbolLibrary}=nothing,
)
    return connect!(
        circuit,
        pin.component,
        pin.spice_order,
        point;
        library=library,
    )
end

function connect!(
    circuit::CircuitDocument,
    point::Tuple{<:Integer,<:Integer},
    pin::CircuitPin;
    library::Union{Nothing,SymbolLibrary}=nothing,
)
    return connect!(
        circuit,
        point,
        pin.component,
        pin.spice_order;
        library=library,
    )
end

"""Add an LTspice net flag, including ground when `name` is `"0"`."""
function addflag!(
    circuit::CircuitDocument,
    position::Tuple{<:Integer,<:Integer},
    name::AbstractString,
)
    flag_name = _validate_record_value(name, "flag name")
    any(isspace, flag_name) && throw(ArgumentError("flag name cannot contain whitespace"))
    x, y = Int.(position)
    record = "FLAG $x $y $flag_name$(_circuit_newline(circuit))"
    _insert_before_prefix!(circuit, [record], ("SYMBOL ", "TEXT "))
    return circuit
end

"""Add a visible LTspice SPICE directive at a schematic position."""
function adddirective!(
    circuit::CircuitDocument,
    directive::AbstractString;
    position::Tuple{<:Integer,<:Integer}=(16, 16),
    alignment::AbstractString="Left",
    size::Integer=2,
)
    directive_text = _validate_record_value(directive, "directive")
    startswith(directive_text, "!") || (directive_text = "!" * directive_text)
    alignment_text = _validate_record_value(alignment, "alignment")
    any(isspace, alignment_text) &&
        throw(ArgumentError("alignment cannot contain whitespace"))
    x, y = Int.(position)
    push!(circuit.records,
          "TEXT $x $y $alignment_text $(Int(size)) $directive_text$(_circuit_newline(circuit))")
    return circuit
end

"""
    readcircuit(path) -> CircuitDocument

Read an LTspice schematic while preserving every source record and line ending.
The file encoding is detected using `circuitfileencoding`.
"""
function readcircuit(path::AbstractString)
    isfile(path) || throw(ArgumentError("LTspice circuit file does not exist: $path"))

    encoding = circuitfileencoding(path)
    records = open(path, encoding) do io
        collect(eachline(io; keep=true))
    end

    isempty(records) &&
        throw(ArgumentError("LTspice circuit file is empty: $path"))

    return CircuitDocument(records, encoding, abspath(path))
end

"""
    writecircuit(path, circuit; encoding=circuit.encoding) -> String

Write an LTspice circuit document to `path`.

Records are written exactly as stored, so reading and writing an unmodified
document preserves its textual structure. Returns the absolute output path.
"""
function writecircuit(
    path::AbstractString,
    circuit::CircuitDocument;
    encoding=circuit.encoding,
)
    outputpath = abspath(path)
    parent = dirname(outputpath)
    isdir(parent) || mkpath(parent)

    open(outputpath, encoding, "w") do io
        for record in circuit.records
            write(io, record)
        end
    end

    return outputpath
end

Base.length(circuit::CircuitDocument) = length(circuit.records)
Base.getindex(circuit::CircuitDocument, index::Integer) = circuit.records[index]
Base.setindex!(
    circuit::CircuitDocument,
    record::AbstractString,
    index::Integer,
) = (circuit.records[index] = String(record))
Base.iterate(circuit::CircuitDocument, state...) =
    iterate(circuit.records, state...)