var d1: u32 = 0xdddddddd;
var d2: [2000]u32 = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } ++ [_]u32{0} ** 1990;
var d3: [2000]u32 = [_]u32{ 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 } ++ [_]u32{0} ** 1990;
var d4: [2000]u32 = [_]u32{ 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 } ++ [_]u32{0} ** 1990;

var b1: u32 = undefined;
var b2: [4]u32 = undefined;

export fn main() u32 {
    // workaround for optimizer removing the arrays since they are not used in a way that is visible to the optimizer
	const d2v: [*]volatile u32 = @ptrCast(&d2);
	const d3v: [*]volatile u32 = @ptrCast(&d3);
	const d4v: [*]volatile u32 = @ptrCast(&d4);

	b2[3] = 0x08675309;
	b1 = d1;

	d3v[0] = 0x12345678;
	d2v[0] = 0x87654321;

	d4v[1999] = d2v[0];


	return 0;
}
