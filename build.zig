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

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    var turtle = b.addExecutable(.{
        .name = "turtle",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    turtle.linkSystemLibrary("glib-2.0");
    turtle.linkSystemLibrary("readline");
    turtle.linkLibC();

    b.installArtifact(turtle);
}
