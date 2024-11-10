const std = @import("std");

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

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var cli = b.addExecutable(.{
        .name = "turtle",
        .root_source_file = b.path("./src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    cli.linkSystemLibrary("glib-2.0");
    cli.linkSystemLibrary("readline");

    b.installArtifact(cli);
}
