const std = @import("std");
const ray = @cImport(@cInclude("raylib.h"));

const screen_width: u32 = 1440;
const screen_height: u32 = 960;

const Button = struct {
    is_down: bool,
    is_released: bool,
    is_pressed: bool,
};

const MouseState = struct {
    position: Vector2,
    left_button: Button,
    right_button: Button,

    fn getState() MouseState {
        const left_button = Button{
            .is_down = if (ray.IsMouseButtonDown(ray.MOUSE_BUTTON_LEFT)) true else false,
            .is_released = if (ray.IsMouseButtonReleased(ray.MOUSE_BUTTON_LEFT)) true else false,
            .is_pressed = if (ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT)) true else false,
        };

        const right_button = Button{
            .is_down = if (ray.IsMouseButtonDown(ray.MOUSE_BUTTON_RIGHT)) true else false,
            .is_released = if (ray.IsMouseButtonReleased(ray.MOUSE_BUTTON_RIGHT)) true else false,
            .is_pressed = if (ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_RIGHT)) true else false,
        };

        const mouse_position = ray.GetMousePosition();
        return MouseState{ .position = .{ .x = mouse_position.x, .y = mouse_position.y }, .left_button = left_button, .right_button = right_button };
    }
};

fn add_vector2(a: ray.Vector2, b: ray.Vector2) ray.Vector2 {
    return ray.Vector2{
        .x = a.x + b.x,
        .y = a.y + b.y,
    };
}

fn Rect(comptime T: type) type {
    return struct {
        const Self = @This();

        x: T,
        y: T,
        width: T,
        height: T,

        pub fn fullyContains(self: Self, other: Self) bool {
            if (other.x < self.x) return false;
            if (other.y < self.y) return false;
            if (other.x + other.width > self.x + self.width) return false;
            if (other.y + other.height > self.y + self.height) return false;

            return true;
        }

        pub fn fullyContainedBy(self: Self, other: Self) bool {
            if (self.x < other.x) return false;
            if (self.y < other.y) return false;
            if (self.x + self.width > other.x + other.width) return false;
            if (self.y + self.height > other.y + other.height) return false;

            return true;
        }

        pub fn overlaps(self: Self, other: Self) bool {
            if (self.x + self.width < other.x or other.x + other.width < self.x) {
                return false;
            }

            if (self.y + self.height < other.y or other.y + other.height < self.y) {
                return false;
            }

            return true;
        }

        pub fn intersection(self: Self, other: Self) ?Self {
            if (!self.overlaps(other)) {
                return null;
            }
            const x1 = if (self.x > other.x) self.x else other.x;
            const y1 = if (self.y > other.y) self.y else other.y;
            const x2 = if ((self.x + self.width) < (other.x + other.width)) self.x + self.width else other.x + other.width;
            const y2 = if ((self.y + self.height) < (other.y + other.height)) self.y + self.height else other.y + other.height;

            return Self{
                .x = x1,
                .y = y1,
                .width = x2 - x1,
                .height = y2 - y1,
            };
        }

        pub fn containsPoint(self: Self, x: T, y: T) bool {
            if (x < self.x) return false;
            if (x > self.x + self.width) return false;
            if (y < self.y) return false;
            if (y > self.y + self.height) return false;

            return true;
        }
    };
}

const Vector2 = struct {
    x: f32,
    y: f32,

    fn fromRayVector(vec: ray.Vector2) Vector2 {
        return .{
            .x = vec.x,
            .y = vec.y,
        };
    }
};

const Vector2Int = struct {
    x: u32,
    y: u32,

    fn toVector2(self: Vector2Int) Vector2 {
        return .{
            .x = @floatFromInt(self.x),
            .y = @floatFromInt(self.y),
        };
    }
};

fn tileIdxToTileCoords(tile_idx: u32, dimensions: Vector2Int) Vector2Int {
    return .{
        .x = if (tile_idx != 0) tile_idx % dimensions.x else 0,
        .y = if (tile_idx != 0) @divFloor(tile_idx, dimensions.x) else 0,
    };
}

const TileSet = struct {
    texture: ray.Texture,
    tilesize: Vector2Int,
    dimensions: Vector2Int,
    tilecount: u32,

    fn init(tileset_name: [:0]const u8, tilesize: Vector2Int) TileSet {
        const texture = ray.LoadTexture(@ptrCast(tileset_name));
        const texture_width: u32 = @intCast(texture.width);
        const texture_height: u32 = @intCast(texture.height);
        const dimensions: Vector2Int = .{
            .x = texture_width / tilesize.x,
            .y = texture_height / tilesize.y,
        };
        return TileSet{
            .texture = texture,
            .tilesize = tilesize,
            .dimensions = dimensions,
            .tilecount = dimensions.x * dimensions.y,
        };
    }

    fn deinit(self: *TileSet) void {
        ray.UnloadTexture(self.texture);
    }

    fn get_frame_rect(self: TileSet, tile_idx: u32) ray.Rectangle {
        const tile_coord = tileIdxToTileCoords(tile_idx, self.dimensions);
        return ray.Rectangle{
            .x = @floatFromInt(tile_coord.x * self.tilesize.x),
            .y = @floatFromInt(tile_coord.y * self.tilesize.y),
            .width = @floatFromInt(self.tilesize.x),
            .height = @floatFromInt(self.tilesize.y),
        };
    }

    fn draw_tile(self: TileSet, tileset_idx: u32, position: Vector2) void {
        const frame_rect = self.get_frame_rect(tileset_idx);
        ray.DrawTextureRec(
            self.texture,
            frame_rect,
            ray.Vector2{ .x = position.x, .y = position.y },
            ray.WHITE,
        );
    }
};

const TileSetPicker = struct {
    position: Vector2,
    tileset: *TileSet,
    tileset_dimensions: Vector2,
    tileset_offset: Vector2,
    current_tile: u32,
    visible: bool,
    zoom_level: u32 = 1,
    zoom_factor: f32 = 1.5,
    picker_rect: ray.Rectangle,
    render_texture: ray.RenderTexture2D,

    fn init(position: Vector2, tileset_offset: Vector2, tileset: *TileSet) TileSetPicker {
        const tileset_dimensions: Vector2 = .{
            .x = @floatFromInt(tileset.texture.width),
            .y = @floatFromInt(tileset.texture.height),
        };

        const picker_rect = ray.Rectangle{
            .x = position.x,
            .y = position.y,
            .width = tileset_offset.x * 2.0 + tileset_dimensions.x,
            .height = tileset_offset.y * 2.0 + tileset_dimensions.y,
        };

        const width: c_int = @intFromFloat(picker_rect.width);
        const height: c_int = @intFromFloat(picker_rect.height);

        var tileset_picker = TileSetPicker{
            .position = position,
            .tileset = tileset,
            .tileset_dimensions = tileset_dimensions,
            .tileset_offset = tileset_offset,
            .current_tile = 0,
            .visible = false,
            .picker_rect = picker_rect,
            .render_texture = ray.LoadRenderTexture(width, height),
        };

        tileset_picker.initialDraw();
        return tileset_picker;
    }

    fn initialDraw(self: TileSetPicker) void {
        ray.BeginTextureMode(self.render_texture);
        ray.ClearBackground(ray.GRAY);

        var i: u32 = 0;
        while (i < self.tileset.tilecount) : (i += 1) {
            const frame_rect = self.tileset.get_frame_rect(i);
            const position = ray.Vector2{
                .x = self.tileset_offset.x + frame_rect.x,
                .y = self.tileset_offset.y + frame_rect.y,
            };
            ray.DrawTextureRec(self.tileset.texture, frame_rect, position, ray.WHITE);
        }
        ray.EndTextureMode();
    }

    fn deinit(self: *TileSetPicker) void {
        ray.UnloadRenderTexture(self.render_texture);
    }

    fn mouseOverPicker(self: TileSetPicker, mouse_position: Vector2) bool {
        if (!self.visible) return false;
        var rect: Rect(f32) = .{
            .x = self.picker_rect.x,
            .y = self.picker_rect.y,
            .width = self.picker_rect.width,
            .height = self.picker_rect.height,
        };
        return rect.containsPoint(mouse_position.x, mouse_position.y);
    }

    fn update(self: *TileSetPicker, mouse_state: MouseState) void {
        if (ray.IsKeyPressed(ray.KEY_P)) {
            self.zoom_level += 1;
        }
        if (ray.IsKeyPressed(ray.KEY_L)) {
            self.zoom_level -= 1;
        }
        if (!self.mouseOverPicker(mouse_state.position)) return;
        const tile_position = Vector2{
            .x = mouse_state.position.x - self.tileset_offset.x - self.position.x,
            .y = mouse_state.position.y - self.tileset_offset.y - self.position.y,
        };
        if (tile_position.x < 0 or tile_position.y < 0) {
            return;
        }

        const tile_width: f32 = @floatFromInt(self.tileset.tilesize.x);
        const tile_height: f32 = @floatFromInt(self.tileset.tilesize.x);
        const tile_x: f32 = tile_position.x / tile_width;
        const tile_y: f32 = tile_position.y / tile_height;
        const tile_coord: Vector2Int = .{
            .x = @intFromFloat(tile_x),
            .y = @intFromFloat(tile_y),
        };

        if (mouse_state.left_button.is_pressed) {
            self.current_tile = tile_coord.y * self.tileset.dimensions.x + tile_coord.x;
        }
    }

    fn draw(self: TileSetPicker) void {
        ray.DrawTextureRec(
            self.render_texture.texture,
            ray.Rectangle{
                .x = 0,
                .y = 0,
                .width = self.picker_rect.width,
                .height = -self.picker_rect.height,
            },
            ray.Vector2{ .x = self.picker_rect.x, .y = self.picker_rect.y },
            ray.WHITE,
        );

        var selected = self.tileset.get_frame_rect(self.current_tile);
        selected.x += self.tileset_offset.x + self.position.x;
        selected.y += self.tileset_offset.y + self.position.y;
        ray.DrawRectangleLinesEx(selected, 1.0, ray.RED);
    }
};

// probably should minimize the size
const Tile = struct {
    tileset_idx: u32,
    occupied: bool,
};

const Chunk = struct {
    texture: ?ray.RenderTexture2D,
};

const Layer = struct {
    tiles: std.ArrayList(Tile),
    tile_dims: Vector2Int,

    fn init(allocator: std.mem.Allocator, map_size: Vector2Int, tile_size: Vector2Int) !Layer {
        const tile_dims = Vector2Int{
            .x = map_size.x / tile_size.x,
            .y = map_size.y / tile_size.y,
        };
        const num_tiles = tile_dims.x * tile_dims.y;
        var layer = Layer{
            .tiles = try std.ArrayList(Tile).initCapacity(allocator, num_tiles),
            .tile_dims = tile_dims,
        };

        layer.tiles.appendNTimesAssumeCapacity(
            .{
                .tileset_idx = 0,
                .occupied = false,
            },
            num_tiles,
        );

        return layer;
    }

    fn deinit(self: *Layer) void {
        self.tiles.deinit();
    }
};

const TileMap = struct {
    map_bounds: Rect(f32),
    tile_dims: Vector2Int,
    tile_size: Vector2Int,
    chunk_size: Vector2Int,
    layer_dims: Vector2Int,
    active_layer: u32,
    layers: std.ArrayList(Layer),
    chunks: std.ArrayList(ray.RenderTexture2D),

    fn init(allocator: std.mem.Allocator, map_size: Vector2Int, chunk_size: Vector2Int, tile_size: Vector2Int, initial_layers: usize) !TileMap {
        const layer_dims = Vector2Int{
            .x = map_size.x / chunk_size.x,
            .y = map_size.y / chunk_size.y,
        };
        const num_chunks = layer_dims.x * layer_dims.y;
        var tilemap = TileMap{
            .map_bounds = Rect(f32){
                .x = 0,
                .y = 0,
                .width = @floatFromInt(map_size.x),
                .height = @floatFromInt(map_size.y),
            },
            .tile_dims = Vector2Int{ .x = map_size.x / tile_size.x, .y = map_size.y / tile_size.y },
            .tile_size = tile_size,
            .chunk_size = chunk_size,
            .layer_dims = layer_dims,
            .active_layer = 0,
            .layers = try std.ArrayList(Layer).initCapacity(allocator, initial_layers),
            .chunks = try std.ArrayList(ray.RenderTexture2D).initCapacity(allocator, num_chunks),
        };

        for (0..initial_layers) |_| {
            try tilemap.layers.append(try Layer.init(allocator, map_size, tile_size));
        }

        for (0..num_chunks) |_| {
            try tilemap.chunks.append(tilemap.createChunk());
        }

        return tilemap;
    }

    fn createChunk(self: *TileMap) ray.RenderTexture2D {
        const texture = ray.LoadRenderTexture(@intCast(self.chunk_size.x), @intCast(self.chunk_size.y));
        ray.BeginTextureMode(texture);
        ray.ClearBackground(ray.BLANK);
        ray.EndTextureMode();
        return texture;
    }

    fn worldPositionToChunkCoords(self: TileMap, world_position: Vector2) Vector2Int {
        const world_x: u32 = @intFromFloat(world_position.x);
        const world_y: u32 = @intFromFloat(world_position.y);
        return .{
            .x = world_x / self.chunk_size.x,
            .y = world_y / self.chunk_size.y,
        };
    }

    fn worldToTileCoords(self: TileMap, world_position: Vector2) Vector2Int {
        const tile_size_x: f32 = @floatFromInt(self.tile_size.x);
        const tile_size_y: f32 = @floatFromInt(self.tile_size.y);
        return Vector2Int{
            .x = @intFromFloat(world_position.x / tile_size_x),
            .y = @intFromFloat(world_position.y / tile_size_y),
        };
    }

    // I think this should take in a tilecoord and not a world position.
    // Do the conversion beforehand
    fn paintTile(self: *TileMap, tile_coords: Vector2Int, current_tile: u32, tileset: TileSet) void {
        const tile_idx: u32 = tile_coords.y * self.tile_dims.x + tile_coords.x;
        var tile: *Tile = &self.layers.items[self.active_layer].tiles.items[tile_idx];
        if (tile.occupied == true and tile.tileset_idx == current_tile) {
            return;
        }
        tile.tileset_idx = current_tile;
        tile.occupied = true;

        const tile_world_pos = Vector2Int{
            .x = (tile_coords.x * self.tile_size.x),
            .y = (tile_coords.y * self.tile_size.y),
        };

        const chunk_coords = Vector2Int{
            .x = tile_world_pos.x / self.chunk_size.x,
            .y = tile_world_pos.y / self.chunk_size.y,
        };
        const chunk_idx = chunk_coords.y * self.layer_dims.x + chunk_coords.x;

        const tile_chunk_pos: Vector2 = .{
            .x = @floatFromInt(tile_world_pos.x - (chunk_coords.x * self.chunk_size.x)),
            .y = @floatFromInt(tile_world_pos.y - (chunk_coords.y * self.chunk_size.y)),
        };

        // Loop over layers and paint chunk
        ray.BeginTextureMode(self.chunks.items[chunk_idx]);
        ray.DrawRectangleRec(ray.Rectangle{
            .x = tile_chunk_pos.x,
            .y = tile_chunk_pos.y,
            .width = @floatFromInt(self.tile_size.x),
            .height = @floatFromInt(self.tile_size.y),
        }, ray.BLUE);
        for (self.layers.items) |*layer| {
            if (layer.tiles.items[tile_idx].occupied != true) {
                continue;
            }
            tileset.draw_tile(layer.tiles.items[tile_idx].tileset_idx, tile_chunk_pos);
        }
        ray.EndTextureMode();
    }

    fn paintRegion(self: *TileMap, start_tile: Vector2Int, end_tile: Vector2Int, current_tile: u32, tileset: TileSet) void {
        const min_x = @min(start_tile.x, end_tile.x);
        const max_x = @max(start_tile.x, end_tile.x);
        const min_y = @min(start_tile.y, end_tile.y);
        const max_y = @max(start_tile.y, end_tile.y);

        const rect = Rect(u32){
            .x = min_x * self.tile_size.x,
            .y = min_y * self.tile_size.y,
            .width = @max((max_x - min_x + 1) * self.tile_size.x, self.tile_size.x),
            .height = @max((max_y - min_y + 1) * self.tile_size.y, self.tile_size.y),
        };

        const chunk_tile_dims = Vector2Int{
            .x = self.chunk_size.x / self.tile_size.x,
            .y = self.chunk_size.y / self.tile_size.y,
        };
        const ftile_x: f32 = @floatFromInt(self.tile_size.x);
        const ftile_y: f32 = @floatFromInt(self.tile_size.y);
        for (0..self.chunks.items.len) |chunk_idx| {
            const chunk_coords = tileIdxToTileCoords(@intCast(chunk_idx), self.layer_dims);
            const chunk_rect = Rect(u32){
                .x = chunk_coords.x * self.chunk_size.x,
                .y = chunk_coords.y * self.chunk_size.y,
                .width = self.chunk_size.x,
                .height = self.chunk_size.y,
            };
            const intersection = chunk_rect.intersection(rect);
            if (intersection == null) {
                continue;
            }

            const region = Rect(f32){
                .x = @floatFromInt(intersection.?.x - chunk_rect.x),
                .y = @floatFromInt(intersection.?.y - chunk_rect.y),
                .width = @floatFromInt(intersection.?.width),
                .height = @floatFromInt(intersection.?.height),
            };

            // Now figure out bounds within chunk
            ray.BeginTextureMode(self.chunks.items[chunk_idx]);
            ray.DrawRectangleRec(ray.Rectangle{
                .x = region.x,
                .y = region.y,
                .width = region.width,
                .height = region.height,
            }, ray.BLUE);

            const chunk_tile_start = Vector2Int{
                .x = @intFromFloat(region.x / ftile_x),
                .y = @intFromFloat(region.y / ftile_y),
            };

            const chunk_tile_end = Vector2Int{
                .x = @intFromFloat((region.x + region.width) / ftile_x),
                .y = @intFromFloat((region.y + region.height) / ftile_y),
            };

            var chunk_tile = chunk_tile_start;
            while (chunk_tile.x < chunk_tile_end.x) : (chunk_tile.x += 1) {
                chunk_tile.y = chunk_tile_start.y;
                while (chunk_tile.y < chunk_tile_end.y) : (chunk_tile.y += 1) {
                    const tile_chunk_pos = Vector2{
                        .x = @floatFromInt(chunk_tile.x * self.tile_size.x),
                        .y = @floatFromInt(chunk_tile.y * self.tile_size.y),
                    };
                    const world_tile_coords = Vector2Int{
                        .x = (chunk_coords.x * chunk_tile_dims.x) + chunk_tile.x,
                        .y = (chunk_coords.y * chunk_tile_dims.y) + chunk_tile.y,
                    };
                    const tile_idx = world_tile_coords.y * self.tile_dims.x + world_tile_coords.x;
                    var tile: *Tile = &self.layers.items[self.active_layer].tiles.items[tile_idx];
                    tile.occupied = true;
                    tile.tileset_idx = current_tile;
                    for (self.layers.items) |*layer| {
                        if (layer.tiles.items[tile_idx].occupied != true) {
                            continue;
                        }
                        tileset.draw_tile(layer.tiles.items[tile_idx].tileset_idx, tile_chunk_pos);
                    }
                }
            }
            ray.EndTextureMode();
        }
    }

    fn draw(self: *TileMap, camera: ray.Camera2D) void {
        const tile_x: f32 = @floatFromInt(self.tile_size.x);
        const tile_y: f32 = @floatFromInt(self.tile_size.y);
        ray.DrawRectangleLinesEx(
            ray.Rectangle{
                .x = self.map_bounds.x - tile_x,
                .y = self.map_bounds.y - tile_y,
                .width = self.map_bounds.width + tile_x * 2.0,
                .height = self.map_bounds.height + tile_y * 2.0,
            },
            tile_x,
            ray.BLACK,
        );

        const tl = ray.GetScreenToWorld2D(ray.Vector2{ .x = 0, .y = 0 }, camera);
        const br = ray.GetScreenToWorld2D(ray.Vector2{ .x = screen_width, .y = screen_height }, camera);
        const layer_x: f32 = @floatFromInt(self.layer_dims.x * self.chunk_size.x);
        const layer_y: f32 = @floatFromInt(self.layer_dims.y * self.chunk_size.y);
        const tl_chunk = self.worldPositionToChunkCoords(Vector2{
            .x = std.math.clamp(tl.x, 0.0, layer_x),
            .y = std.math.clamp(tl.y, 0.0, layer_y),
        });
        const br_chunk = self.worldPositionToChunkCoords(Vector2{
            .x = std.math.clamp(br.x, 0.0, layer_x),
            .y = std.math.clamp(br.y, 0.0, layer_y),
        });
        var x: u32 = tl_chunk.x;
        var y: u32 = tl_chunk.y;
        const chunk_x: f32 = @floatFromInt(self.chunk_size.x);
        const chunk_y: f32 = @floatFromInt(self.chunk_size.y);
        while (y <= br_chunk.y and y < self.layer_dims.y) : (y += 1) {
            x = 0;
            while (x <= br_chunk.x and x < self.layer_dims.x) : (x += 1) {
                const chunk_idx = y * self.layer_dims.x + x;
                const position = Vector2{
                    .x = @floatFromInt(self.chunk_size.x * x),
                    .y = @floatFromInt(self.chunk_size.y * y),
                };
                ray.DrawTextureRec(
                    self.chunks.items[chunk_idx].texture,
                    ray.Rectangle{
                        .x = 0,
                        .y = 0,
                        .width = chunk_x,
                        .height = -1.0 * chunk_y,
                    },
                    ray.Vector2{
                        .x = position.x,
                        .y = position.y,
                    },
                    ray.WHITE,
                );
            }
        }
    }

    fn deinit(self: *TileMap) void {
        for (self.chunks.items) |*chunk| {
            ray.UnloadRenderTexture(chunk.*);
        }
        self.chunks.deinit();

        for (self.layers.items) |*layer| {
            layer.deinit();
        }
        self.layers.deinit();
    }
};

fn handleInput() void {}

const DragState = struct {
    dragging: bool,
    start_drag: ?Vector2Int,

    fn reset(self: *DragState) void {
        self.dragging = false;
        self.start_drag = null;
    }
};

pub fn main() !void {
    // Rewrite considerations:
    // use more floats! The type conversions are super annoying
    // Do something about draw order? More generalized solution for overlapping?

    const tile_width = 24;
    const tile_height = 24;

    // In Tiles
    const tilemap_dims = Vector2Int{ .x = screen_width * 5, .y = screen_height * 5 };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    //ray.SetConfigFlags(ray.FLAG_VSYNC_HINT);
    ray.InitWindow(screen_width, screen_height, "zig raylib example");
    defer ray.CloseWindow();
    //ray.SetTargetFPS(144);
    var display_text: [20]u8 = undefined;
    var layer_text: [20]u8 = undefined;
    var coord_text: [20]u8 = undefined;

    var tilemap = try TileMap.init(
        allocator,
        tilemap_dims,
        Vector2Int{ .x = screen_width, .y = screen_height },
        Vector2Int{ .x = tile_width, .y = tile_width },
        5,
    );
    defer tilemap.deinit();

    var tileset = TileSet.init("resources/uf_map.png", Vector2Int{ .x = tile_width, .y = tile_height });
    defer tileset.deinit();

    var tileset_picker = TileSetPicker.init(
        Vector2{ .x = 20, .y = 20 },
        Vector2{ .x = 20, .y = 20 },
        &tileset,
    );
    defer tileset_picker.deinit();

    var camera = ray.Camera2D{};
    camera.target = ray.Vector2{
        .x = tilemap_dims.x / 2,
        .y = tilemap_dims.y / 2,
    };
    camera.offset = ray.Vector2{ .x = screen_width / 2, .y = screen_height / 2 };
    camera.rotation = 0.0;
    camera.zoom = 1.0;
    const movement_speed: f32 = 500.0;
    var drag_mode = DragState{
        .dragging = false,
        .start_drag = null,
    };
    //var end_position: Vector2 = Vector2{ .x = 0, .y = 0 };
    while (!ray.WindowShouldClose()) {
        // Get Input
        const mouse_state = MouseState.getState();
        const key_pressed = ray.GetKeyPressed();

        // cap this
        camera.zoom += (ray.GetMouseWheelMove() * 0.05);
        camera.zoom = std.math.clamp(camera.zoom, 0.05, 2);

        // Text Handling
        const fps = ray.GetFPS();
        const output = try std.fmt.bufPrint(&display_text, "FPS: {d}", .{fps});
        display_text[output.len] = 0;

        const layer_output = try std.fmt.bufPrint(&layer_text, "Layer: {d}", .{tilemap.active_layer});
        layer_text[layer_output.len] = 0;

        if (key_pressed == ray.KEY_T) {
            tileset_picker.visible = !tileset_picker.visible;
        }

        if (ray.IsKeyDown(ray.KEY_W)) {
            camera.target.y -= movement_speed * ray.GetFrameTime() * 1.0 / camera.zoom;
        }
        if (ray.IsKeyDown(ray.KEY_A)) {
            camera.target.x += -movement_speed * ray.GetFrameTime() * 1.0 / camera.zoom;
        }
        if (ray.IsKeyDown(ray.KEY_S)) {
            camera.target.y += movement_speed * ray.GetFrameTime() * 1.0 / camera.zoom;
        }
        if (ray.IsKeyDown(ray.KEY_D)) {
            camera.target.x += movement_speed * ray.GetFrameTime() * 1.0 / camera.zoom;
        }

        if (ray.IsKeyDown(ray.KEY_LEFT_SHIFT) and !drag_mode.dragging) {
            drag_mode.dragging = true;
            drag_mode.start_drag = null;
        }

        if (ray.IsKeyUp(ray.KEY_LEFT_SHIFT)) {
            drag_mode.reset();
        }

        if (ray.IsKeyPressed(ray.KEY_F)) {
            tilemap.paintRegion(Vector2Int{ .x = 0, .y = 0 }, Vector2Int{ .x = tilemap.tile_dims.x - 1, .y = tilemap.tile_dims.y - 1 }, tileset_picker.current_tile, tileset);
        }

        tilemap.active_layer = switch (key_pressed) {
            ray.KEY_KP_0 => 0,
            ray.KEY_KP_1 => 1,
            ray.KEY_KP_2 => 2,
            ray.KEY_KP_3 => 3,
            ray.KEY_KP_4 => 4,
            else => tilemap.active_layer,
        };

        const mouse_over_ui = tileset_picker.mouseOverPicker(mouse_state.position);
        const world_position = Vector2.fromRayVector(ray.GetScreenToWorld2D(ray.Vector2{ .x = mouse_state.position.x, .y = mouse_state.position.y }, camera));

        if (!mouse_over_ui and tilemap.map_bounds.containsPoint(world_position.x, world_position.y)) {
            const tile_coord = tilemap.worldToTileCoords(world_position);
            const coord_output = try std.fmt.bufPrint(&coord_text, "({d},{d})", .{ tile_coord.x, tile_coord.y });
            coord_text[coord_output.len] = 0;

            if (mouse_state.left_button.is_down) {
                if (drag_mode.dragging) {
                    if (drag_mode.start_drag == null) {
                        drag_mode.start_drag = tile_coord;
                    }
                } else {
                    tilemap.paintTile(tile_coord, tileset_picker.current_tile, tileset);
                }
            } else if (mouse_state.left_button.is_released and drag_mode.dragging) {
                const start_drag = drag_mode.start_drag.?;

                tilemap.paintRegion(start_drag, tile_coord, tileset_picker.current_tile, tileset);
                drag_mode.reset();
            }
        }

        if (tileset_picker.visible) {
            tileset_picker.update(mouse_state);
        }

        ray.BeginDrawing();
        ray.ClearBackground(ray.BLUE);

        ray.BeginMode2D(camera);
        tilemap.draw(camera);
        ray.EndMode2D();

        if (tileset_picker.visible) {
            tileset_picker.draw();
        }

        ray.DrawText(@ptrCast(&display_text), 5, 5, 20, ray.WHITE);
        ray.DrawText(@ptrCast(&layer_text), 1350, 5, 20, ray.WHITE);
        ray.DrawText(@ptrCast(&coord_text), 1350, 940, 20, ray.WHITE);

        ray.EndDrawing();
    }
}
