# RITZ

RITZ is a Zig implementation of an RV32 interpreter inspired by **rvddt** (RISC-V Dynamic Debugging Tool).

It provides:

- A simple RV32 CPU execution core
- In-memory program loading
- Interactive monitor commands for stepping, tracing, register dumps, and memory dumps
- Basic device hooks (console and memcard)

## Credits

RITZ is based on **rvddt** by **John Winans**:

- https://github.com/johnwinans/rvddt

The original `rvddt` was created to help generate material for the `rvalp` book project:

- https://github.com/johnwinans/rvalp

It is a practical instructional debugger for RV32I programs.

## Quick Start

From the project root:

```bash
zig build --summary all
zig build run
```

You should see a `ritz>` prompt. Quick sanity check:

```text
ritz> r
ritz> t 5
ritz> d 0x0 0x40
ritz> x
```

Load and run a raw memory image:

```bash
zig build run -- -s 0x0 -l 0x10000 -f program.bin
```

Then at `ritz>`:

```text
ritz> r
ritz> t 0x0 10
ritz> g
ritz> x
```

Typical workflow is to build a raw RV32 binary image with entry at `0x0`, load it with `-f`, then trace (`t`/`ti`) or run (`g`).

## Build

Requirements:

- Zig (recent stable version)

Note on tool dependencies:

- The long-term intention is to depend only on the Zig compiler.
- Due to an `objcopy` bug in Zig `0.15.2`, external RISC-V `objcopy` tools are currently required for sample artifact generation.
- If assembly listings are desired, an external RISC-V `objdump` tool is also required.

Build the project:

```bash
zig build --summary all
```

The executable is built as `ritz`.

## Run

Run with Zig build step:

```bash
zig build run
```

Pass program arguments after `--`:

```bash
zig build run -- -s 0x0 -l 0x10000 -f program.bin
```

CLI options:

- `-s <memstart>`: memory start address (decimal or hex like `0x1000`)
- `-l <memlen>`: memory length in bytes
- `-f <memimage>`: raw image file to load at `memstart`

## Samples (Top Level)

From the repository root:

```bash
zig build samples
```

Builds all sample firmware under `samples/` and generates `.bin`/`.lst` artifacts.

Run samples with the compiled `ritz` emulator:

```bash
zig build samples-run
```

Run a specific sample (example: `stand01`):

```bash
zig build samples-run -Dsample=stand01
```

Run samples in QEMU:

```bash
zig build samples-qemu-run
```

Run one sample in QEMU:

```bash
zig build samples-qemu-run -Dsample=stand01
```

If QEMU is not on PATH, provide it explicitly:

```bash
zig build samples-qemu-run -Dsample=stand01 
-Dqemu="C:/Program Files/qemu/qemu-system-riscv32.exe"
```

## Tests (Top Level)

From the repository root, use the top-level test steps:

```bashzig build samples-qemu-run -Dsample=stand01 
zig build tests
zig build tests-run
zig build tests-clean
```

These steps delegate to `tests/build.zig` internally and avoid shell-specific path issues.

Note about direct sub-build usage:

- Preferred: `zig build tests-run` and `zig build tests-clean`
- Avoid relying on `zig build --build-file tests/build.zig ...` unless you are intentionally working inside the tests build script.

## Clean

Remove build/cache contents (directories are kept):

```bash
zig build clean
```

## Interactive Commands

At the `ritz>` prompt:

- `?` show help
- `r` dump CPU registers
- `t [[addr] qty]` trace instructions with register dumps
- `ti [[addr] qty]` trace instructions without register dumps
- `g [[addr] [qty]]` run continuously for qty (optionally set `pc` first), qty = 0 -> execute until break
- `d [addr [len]]` dump memory
- `a` toggle register ABI names/x-names display
- `> filename` redirect output to file (`> -` restores stdout)
- `x` exit

## Notes

- Default memory range is `memstart=0` and `memlen=0x10000`.
- Stack pointer (`sp`) is initialized to the top of the configured memory region.
- Focus is RV32I-style execution and interactive tracing/debugging.
- Execution stops on illegal instructions or `ebreak`.
- Like original `rvddt`, this is primarily a static debugging workflow (no interactive register/memory editing commands).


.\zig-out\bin\ritz.exe -l 0x20000 -f .\tests\firmware\firmware.bin