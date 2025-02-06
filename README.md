# Unravel - CLI parser in Zig

## WARNING: This libarary is currently in an unuseable state!

Unravel is a CLI parser library, primarily made for the [orbc](https://github.com/OrbLang/orbc) compiler.

## Why?

Unravel is intended to make it easy, and efficient, to set up CLI arguments.
Most parsers use many function calls, or weird nested blobs, to set up arguments, which can be annoying and hard to read.
Unravel aims to fix this, by using a simple list of `ArgDef`'s, and by outputting the parsed arguments and their values, in a struct.

An example of some arguments could look like:

```zig

pub const arguments: ArgDefs = &.{
    .{
        .name = "foo",
        .short = 'f',
        .long = "foo",
        .type = .String ,
        .help = "--foo takes a string",
    },
    .{
        .name = "bar",
        .short = 'b'
        .long = "bar",
        .type = .Uint ,
        .help = "--bar takes an unsigned int",
    },
}
```
