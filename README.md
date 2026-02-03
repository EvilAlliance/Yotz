# Yots

Compiler to fasm linux x86-64

## Acknowledgement 

File: [DiffMatchPatch.zig](./test/DiffMatchPatch.zig) extracted from [github](https://github.com/mnemnion/diffz/tree/more-port)

## Execute Project

### Build Project

```console
zig build
```

Ouput executable will be in ./zig-out/bin/yot

### Build and Run Project

```console
zig build run
```

Ouput executable will be in ./zig-out/bin/yot

## Usage - Subcommands

### Build

```console
yot build <src>
```

### Build and Run

```console
yot run <src> <...args> -- <...executable args>
```

### Simulation

Interpreter of the same language, the output should be the same

```console
yot sim <src> <...args> -- <...executable args>
```

### Lex

Output file with tokens

```console
yot lex <src> <...args> -- <...executable args>
```

### Parse

Output file with the statements

```console
yot parse <src> <...args> -- <...executable args>
```
### Check

Output file with the result of the checking proccess

```console
yot check <src> <...args> -- <...executable args>
```

### IR

Output file with the intermediate represetation

```console
yot ir <src> <...args> -- <...executable args>
```

## Arguments

### Change Output to stdout

-stdout will change the output to stdout instead  of a file

### Bench

-b will tell you how long each thing takes

### Silence

-s the output will be only errors

Silence will force bench to not work because output will be close except for errors

## Sintax

Exmples in Example folder

## Perf

```console
perf stat -e   cache-references,cache-misses,L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses ./zig-out/bin/yot parse Example/Inference/Inference3.yt --stdout
perf record -e cache-misses --call-graph dwarf ./zig-out/bin/yot parse Example/Inference/Inference3.yt --stdout
hotspot --kallsyms /proc/kallsyms
```
