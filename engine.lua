local bxor = bit32 and bit32.bxor or function(a,b)
    local p,c=1,0
    while a>0 and b>0 do
        local ra,rb=a%2,b%2
        if ra~=rb then c=c+p end
        a,b,p=(a-ra)/2,(b-rb)/2,p*2
    end
    if a<b then a=b end
    while a>0 do
        local ra=a%2
        if ra>0 then c=c+p end
        a,p=(a-ra)/2,p*2
    end
    return c
end

return function(bytecode, opcodes, sbox)
    local pos = 1
    
    local function gBits8()
        local b = string.byte(bytecode, pos, pos)
        pos = pos + 1
        return b
    end
    
    local function gBits32()
        local b1, b2, b3, b4 = string.byte(bytecode, pos, pos + 3)
        pos = pos + 4
        return (b1 * 16777216) + (b2 * 65536) + (b3 * 256) + b4
    end

    local function gBits16()
        local b1, b2 = string.byte(bytecode, pos, pos + 1)
        pos = pos + 2
        return (b1 * 256) + b2
    end

    local function gString(len)
        local str = string.sub(bytecode, pos, pos + len - 1)
        pos = pos + len
        return str
    end

    local inst_len = gBits32()
    local Instructions = {}
    for i = 1, inst_len do
        local op = gBits8()
        local A = gBits8()
        local B = gBits8()
        local Bx = gBits16()
        Instructions[i] = {op, A, B, Bx}
    end
    
    local const_len = gBits32()
    local Constants = {}
    for i = 1, const_len do
        local len = gBits32()
        Constants[i] = gString(len)
    end
    
    local Stack = {}
    local PC = 1
    while true do
        local inst = Instructions[PC]
        if not inst then break end
        
        local mutated_op = inst[1]
        local OP = sbox[mutated_op + 1]
        
        local A = inst[2]
        local B = inst[3]
        local Bx = inst[4]
        
        if OP == opcodes.OP_MOVE then
            Stack[A] = Stack[B]
        elseif OP == opcodes.OP_LOADSTR then
            Stack[A] = Constants[Bx]
        elseif OP == opcodes.OP_CONCAT then
            Stack[A] = Stack[B] .. Stack[Bx]
        elseif OP == opcodes.OP_XOR then
            local str = Stack[B]
            local seed = Bx
            local decrypted = {}
            for i = 1, #str do
                seed = (seed * 1664525 + 1013904223) % 4294967296
                local key_byte = seed % 256
                local char_byte = string.byte(str, i, i)
                decrypted[i] = string.char(bxor(char_byte, key_byte))
            end
            Stack[A] = table.concat(decrypted)
        elseif OP == opcodes.OP_ADD then
            local str = Stack[B]
            local seed = Bx
            local decrypted = {}
            for i = 1, #str do
                seed = (seed * 1664525 + 1013904223) % 4294967296
                local key_byte = seed % 256
                local char_byte = string.byte(str, i, i)
                local dec = char_byte - key_byte
                if dec < 0 then dec = dec + 256 end
                decrypted[i] = string.char(dec)
            end
            Stack[A] = table.concat(decrypted)
        elseif OP == opcodes.OP_REVXOR then
            local str = Stack[B]
            local seed = Bx
            local decrypted = {}
            local len = #str
            for i = 1, len do
                seed = (seed * 1664525 + 1013904223) % 4294967296
                local key_byte = seed % 256
                local char_byte = string.byte(str, i, i)
                decrypted[len - i + 1] = string.char(bxor(char_byte, key_byte))
            end
            Stack[A] = table.concat(decrypted)
        elseif OP == opcodes.OP_ENV then
            local env = getfenv and getfenv() or _G
            Stack[A] = env.loadstring or loadstring
        elseif OP == opcodes.OP_LOADSTRING then
            local loader = Stack[B]
            local source = Stack[Bx]
            if not loader then
                Stack[A] = assert((load or loadstring)(source, "@Lunar_Obfuscated"))
            else
                Stack[A] = assert(loader(source, "@Lunar_Obfuscated"))
            end
        elseif OP == opcodes.OP_CALL then
            Stack[A]()
        elseif OP == opcodes.OP_JMP then
            PC = PC + Bx
            goto skip_pc_inc
        elseif OP == opcodes.OP_JMP_TRUE then
            if Stack[A] then
                PC = PC + Bx
                goto skip_pc_inc
            end
        elseif OP == opcodes.OP_TRASH then
        elseif OP == opcodes.OP_HALT then
            break
        end
        
        ::skip_pc_inc::
        PC = PC + 1
    end
end
