const memptr = @volatileCast(@as(*u32, @ptrFromInt(0x1F00)));

export var b1: u32 = 0;
export var b2 = [_]u32{0} ** 4;

export fn main() u32 {
    b1 = 0xCAFEBABE;
    b2[3] = 0xDEADBEEF;

    memptr.* = b1;
    memptr.* = b2[3];
    return 0;
}
