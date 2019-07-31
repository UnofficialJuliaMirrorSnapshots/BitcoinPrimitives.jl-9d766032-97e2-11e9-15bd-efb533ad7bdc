include("op-codes.jl")

"""
    Script

Script data type has a single `data` field, stored as `Vector{Vector{UInt8}}`
in which each inner `Vector{UInt8}` represent a stack item. It represents
either a PubKey or Signature script.

A script included in outputs which sets the conditions that must be fulfilled
for those satoshis to be spent. Data for fulfilling the conditions can be
provided in a signature script. Pubkey Scripts are called a scriptPubKey in code.

Data generated by a spender which is almost always used as variables to satisfy
a pubkey script. Signature Scripts are called scriptSig in code.
"""
struct Script
    data::Vector{Vector{UInt8}}
end

Script() = Script(Vector{UInt8}[])

function Base.show(io::IO, z::Script)
    for item in z.data
        if length(item) == 1
            if haskey(OP_CODE_NAMES, item[1])
                println(io, OP_CODE_NAMES[item[1]])
            else
                println(io, string("OP_CODE_", Int(item[1])))
            end
        else
            println(io, bytes2hex(item))
        end
    end
end

"""
    Script(::IOBuffer) -> Script

Parse a `Script` from an IOBuffer
"""
function Script(io::IOBuffer)
    length_ = CompactSizeUInt(io).value
    data = Vector{UInt8}[]
    count = 0
    while count < length_
        count += 1
        current_byte = read(io, UInt8)
        if current_byte >= 0x01 && current_byte <= 0x4b
            n = current_byte
            push!(data, read(io, n))
            count += n
        elseif current_byte == 0x4c
            # op_pushdata1
            n = read(io, Int8)
            push!(data, read(io, n))
            count += n + 1
        elseif current_byte == 0x4d
            # op_pushdata2
            n = read(io, Int16)
            push!(data, read(io, n))
            count += n + 2
        else
            # op_code
            push!(data, [current_byte])
        end
    end
    @assert count == length_ "Parsing failed"
    return Script(data)
end

"""
    serialize(s::Script) -> Vector{UInt8}

Serialize a `Script` to a Vector{UInt8}
"""
function serialize(s::Script)
    result = UInt8[]
    for item in s.data
        length_ = length(item)
        if length_ == 1
            append!(result, item)
        else
            length_ = length(item)
            if length_ < 0x4b
                append!(result, UInt8(length_))
            elseif length_ > 0x4b && length_ < 0x100
                append!(result, 0x4c)
                append!(result, UInt8(length_))
            elseif length_ >= 0x100 && length_ <= 0x208
                append!(result, 0x4d)
                result += bytes(length_, len=2)
            else
                error("too long an item")
            end
            append!(result, item)
        end
    end
    total = CompactSizeUInt(length(result))
    prepend!(result, serialize(total))
    return result
end

"""
    script(::Vector{UInt8}; type::Symbol=:P2WSH) -> Script

Returns a `Script` of set type for given hash.
- `type` can be `:P2PKH`, `:P2SH`, `:P2WPKH` or `:P2WSH`
- hash must be 32 bytes long for P2WSH script, 20 for the others
"""
function script(bin::Vector{UInt8}; type::Symbol=:P2PKH)
    if type == :P2WSH
        @assert length(bin) == 32
        return Script([[0x00], bin])
    else
        @assert length(bin) == 20
        if type == :P2PKH
            return Script([[0x76], [0xa9], bin, [0x88], [0xac]])
        elseif type == :P2SH
            return Script([0xa9], bin, [0x87])
        elseif type == :P2WPKH
            return Script([[0x00], bin])
        end
    end
end

"""
    type(script::Script) -> Symbol

Return type of `Script` : `:P2PKH`, `:P2SH`, `:P2WPKH` or `:P2WSH`
"""
function type(script::Script)
    if is_p2pkh(script)
        return :P2PKH
    elseif is_p2sh(script)
        return :P2SH
    elseif is_p2wsh(script)
        return :P2WSH
    elseif is_p2wpkh(script)
        return :P2WPKH
    else
        return error("Unknown Script type")
    end
end

"""
Returns whether this follows the
OP_DUP OP_HASH160 <20 byte hash> OP_EQUALVERIFY OP_CHECKSIG pattern.
"""
function is_p2pkh(script::Script)
    return length(script.data) == 5 &&
        script.data[1] == [0x76] &&
        script.data[2] == [0xa9] &&
        typeof(script.data[3]) == Vector{UInt8} &&
        length(script.data[3]) == 20 &&
        script.data[4] == [0x88] &&
        script.data[5] == [0xac]
end

"""
Returns whether this follows the
OP_HASH160 <20 byte hash> OP_EQUAL pattern.
"""
function is_p2sh(script::Script)
    return length(script.data) == 3 &&
           script.data[1] == [0xa9] &&
           typeof(script.data[2]) == Vector{UInt8} &&
           length(script.data[2]) == 20 &&
           script.data[3] == [0x87]
end

function is_p2wpkh(script::Script)
    length(script.data) == 2 &&
    script.data[1] == [0x00] &&
    typeof(script.data[2]) == Vector{UInt8} &&
    length(script.data[2]) == 20
end

"""
Returns whether this follows the
OP_0 <20 byte hash> pattern.
"""
function is_p2wsh(script::Script)
    length(script.data) == 2 &&
    script.data[1] == [0x00] &&
    typeof(script.data[2]) == Vector{UInt8} &&
    length(script.data[2]) == 32

end

const H160_INDEX = Dict([
    ("P2PKH", 3),
    ("P2SH", 2)
])

"""
Returns the address corresponding to the script
"""
function script2address(script::Script, testnet::Bool)
    type = scripttype(script)
    h160 = script.data[H160_INDEX[type]]
    return h160_2_address(h160, testnet, type)
end