const memptr = @volatileCast(@as(*u32, @ptrFromInt(0x1F00)));

export fn main() u32 {
    const res = 0xBABEFACE;
    memptr.* = res;
    return res;
}
