const mem = @import("std").mem;

pub fn ComptimeStringMap(comptime V: type, comptime Map: anytype) type {
    const map_fields = comptime @typeInfo(@TypeOf(Map)).Struct.fields;

    return struct {
        pub fn get(key: []const u8) ?V {
            inline for (map_fields) |field| {
                if (mem.eql(u8, key, field.name)) {
                    return @field(Map, field.name);
                }
            }

            return null;
        }
    };
}
