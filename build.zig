const Builder = @import("std").build.Builder;

const c_flags = [_][]const u8{
    "-Werror",
    "-Wextra",
    "-Wall",
    "-Wfloat-equal",
    "-Wundef",
    "-Wshadow",
    "-Wpointer-arith",
    "-Wcast-align",
    "-Wstrict-prototypes",
    "-Wstrict-overflow=5",
    "-Wwrite-strings",
    "-Waggregate-return",
    "-Wcast-qual",
    "-Wswitch-default",
    "-Wswitch-enum",
    "-Wconversion",
    "-Wunreachable-code",
    "-Wno-incompatible-pointer-types-discards-qualifiers",

    "-Wno-error=switch-enum",
};

const c_sources = [_][]const u8{
    "src/cmd_executor/cmd_executor.c",
    "src/cmd_executor/errors.c",
    "src/cmd_executor/strings.c",
    "src/cmd_executor/vars.c",
    "src/cmd_parser.c",
    "src/cmd.c",
    "src/utils.c",
};

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    var turtle = b.addExecutable("turtle", "./src/main.zig");
    turtle.setTarget(target);
    turtle.setBuildMode(mode);
    turtle.setOutputDir("./build");
    turtle.linkSystemLibrary("glib-2.0");
    turtle.linkSystemLibrary("readline");
    turtle.addIncludePath("./src");
    turtle.addCSourceFiles(&c_sources, &c_flags);
    turtle.linkLibC();

    turtle.install();
}
