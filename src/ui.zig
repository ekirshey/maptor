const std = @import("std");
const ray = @import("raylib.zig");

pub const Container = struct {};
pub const Button = struct {};

pub const ElementType = union(enum) {
    container: Container,
    button: Button,
};

pub const Element = struct {
    rect: ray.Rectangle,
    element_type: ElementType,
    children: std.ArrayList(Element),
};
