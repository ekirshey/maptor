const std = @import("std");
const ray = @import("raylib.zig");
const ui = @import("ui.zig");

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

        var mouse_position = ray.GetMousePosition();
        return MouseState{ .position = .{ .x = mouse_position.x, .y = mouse_position.y }, .left_button = left_button, .right_button = right_button };
    }
};

fn add_vector2(a: ray.Vector2, b: ray.Vector2) ray.Vector2 {
    return ray.Vector2{
        .x = a.x + b.x,
        .y = a.y + b.y,
    };
}

const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn fullyContains(self: Rect, other: Rect) bool {
        if (other.x < self.x) return false;
        if (other.y < self.y) return false;
        if (other.x + other.width > self.x + self.width) return false;
        if (other.y + other.height > self.y + self.height) return false;

        return true;
    }

    pub fn fullyContainedBy(self: Rect, other: Rect) bool {
        if (self.x < other.x) return false;
        if (self.y < other.y) return false;
        if (self.x + self.width > other.x + other.width) return false;
        if (self.y + self.height > other.y + other.height) return false;

        return true;
    }

    pub fn containsPoint(self: Rect, point: Vector2) bool {
        if (point.x < self.x) return false;
        if (point.x > self.x + self.width) return false;
        if (point.y < self.y) return false;
        if (point.y > self.y + self.height) return false;

        return true;
    }
};

const Vector2 = struct {
    x: f32,
    y: f32,
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

fn tileIdxToVector2Int(tile_idx: u32, dimensions: Vector2Int) Vector2Int {
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
        const tile_coord = tileIdxToVector2Int(tile_idx, self.dimensions);
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
        var tileset_dimensions: Vector2 = .{
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
            var position = ray.Vector2{
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
        var rect: Rect = .{
            .x = self.picker_rect.x,
            .y = self.picker_rect.y,
            .width = self.picker_rect.width,
            .height = self.picker_rect.height,
        };
        return rect.containsPoint(mouse_position);
    }

    fn update(self: *TileSetPicker, mouse_state: MouseState) void {
        if (ray.IsKeyPressed(ray.KEY_P)) {
            self.zoom_level += 1;
        }
        if (ray.IsKeyPressed(ray.KEY_L)) {
            self.zoom_level -= 1;
        }
        if (!self.mouseOverPicker(mouse_state.position)) return;
        var tile_position = Vector2{
            .x = mouse_state.position.x - self.tileset_offset.x - self.position.x,
            .y = mouse_state.position.y - self.tileset_offset.y - self.position.y,
        };
        if (tile_position.x < 0 or tile_position.y < 0) {
            return;
        }

        const tile_width: f32 = @floatFromInt(self.tileset.tilesize.x);
        const tile_height: f32 = @floatFromInt(self.tileset.tilesize.x);
        var tile_x: f32 = tile_position.x / tile_width;
        var tile_y: f32 = tile_position.y / tile_height;
        var tile_coord: Vector2Int = .{
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
    render_texture: ray.RenderTexture2D,
    tiles: std.ArrayList(Tile),
    tile_size: Vector2Int,
    chunk_size: Vector2Int,
    tile_dims: Vector2Int,
    texture_dimensions: Vector2,

    fn init(allocator: std.mem.Allocator, chunk_size: Vector2Int, tile_size: Vector2Int) !Chunk {
        const tile_dims = Vector2Int{
            .x = chunk_size.x / tile_size.x,
            .y = chunk_size.y / tile_size.y,
        };
        const num_tiles: u32 = tile_dims.x * tile_dims.y;
        var chunk = Chunk{
            .render_texture = ray.LoadRenderTexture(@intCast(chunk_size.x), @intCast(chunk_size.y)),
            .tiles = try std.ArrayList(Tile).initCapacity(allocator, num_tiles),
            .tile_size = tile_size,
            .chunk_size = chunk_size,
            .tile_dims = tile_dims,
            .texture_dimensions = Vector2{
                .x = @floatFromInt(chunk_size.x),
                .y = @floatFromInt(chunk_size.y),
            },
        };

        chunk.tiles.appendNTimesAssumeCapacity(
            .{
                .tileset_idx = 0,
                .occupied = false,
            },
            num_tiles,
        );

        ray.BeginTextureMode(chunk.render_texture);
        ray.ClearBackground(ray.BLANK);
        ray.EndTextureMode();

        return chunk;
    }

    fn redraw(self: *Chunk, tileset: TileSet) void {
        ray.BeginTextureMode(self.render_texture);
        ray.ClearBackground(ray.BLANK);
        for (self.tiles.items, 0..) |tile, i| {
            const coords = tileIdxToVector2Int(@intCast(i), self.tile_dims);
            var world_pos: Vector2 = .{
                .x = @floatFromInt(self.tile_size.x * coords.x),
                .y = @floatFromInt(self.tile_size.y * coords.y),
            };
            if (tile.occupied) {
                tileset.draw_tile(tile.tileset_idx, world_pos);
            }
        }
        ray.EndTextureMode();
    }

    fn paintTile(self: *Chunk, tile_idx: u32, tileset_idx: u32, tileset: TileSet) void {
        var tile = &self.tiles.items[tile_idx];
        tile.tileset_idx = tileset_idx;
        ray.BeginTextureMode(self.render_texture);

        const coords = tileIdxToVector2Int(tile_idx, self.tile_dims);
        var world_pos: Vector2 = .{
            .x = @floatFromInt(self.tile_size.x * coords.x),
            .y = @floatFromInt(self.tile_size.y * coords.y),
        };

        tileset.draw_tile(tile.tileset_idx, world_pos);

        ray.EndTextureMode();
    }

    fn draw(self: Chunk) void {
        ray.DrawTextureRec(
            self.render_texture.texture,
            ray.Rectangle{
                .x = 0,
                .y = 0,
                .width = self.texture_dimensions.x,
                .height = -1.0 * self.texture_dimensions.y,
            },
            ray.Vector2{ .x = 0, .y = 0 },
            ray.WHITE,
        );
    }

    fn deinit(self: *Chunk) void {
        ray.UnloadRenderTexture(self.render_texture);
        self.tiles.deinit();
    }
};

const Layer = struct {
    chunks: std.ArrayList(Chunk),
    map_size: Vector2Int,
    chunk_size: Vector2Int,
    tile_size: Vector2Int,

    fn init(allocator: std.mem.Allocator, map_size: Vector2Int, chunk_size: Vector2Int, tile_size: Vector2Int) !Layer {
        const chunk_dims = Vector2Int{
            .x = map_size.x / chunk_size.x,
            .y = map_size.y / chunk_size.y,
        };
        const num_chunks = chunk_dims.x * chunk_dims.y;
        var layer = Layer{
            .chunks = try std.ArrayList(Chunk).initCapacity(allocator, num_chunks),
            .map_size = map_size,
            .chunk_size = chunk_size,
            .tile_size = tile_size,
        };

        for (0..num_chunks) |_| {
            try layer.chunks.append(try Chunk.init(allocator, chunk_size, tile_size));
        }

        return layer;
    }

    fn paintTile(self: *Layer) void {
        _ = self;
    }

    fn draw(self: Layer, camera: ray.Camera2D) void {
        _ = self;
        _ = camera;
    }
};

const TileMap = struct {
    map_bounds: Rect,
    tile_dims: Vector2Int,
    tile_size: Vector2Int,
    active_layer: u32,
    layers: std.ArrayList(Chunk),

    fn init(allocator: std.mem.Allocator, map_size: Vector2Int, tile_size: Vector2Int, initial_layers: usize) !TileMap {
        var tilemap = TileMap{
            .map_bounds = Rect{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(map_size.x),
                .height = @floatFromInt(map_size.y),
            },
            .tile_dims = Vector2Int{ .x = map_size.x / tile_size.x, .y = map_size.y / tile_size.y },
            .tile_size = tile_size,
            .active_layer = 0,
            .layers = try std.ArrayList(Chunk).initCapacity(allocator, initial_layers),
        };

        for (0..initial_layers) |_| {
            try tilemap.layers.append(try Chunk.init(allocator, map_size, tile_size));
        }

        return tilemap;
    }

    fn worldToTileCoords(self: TileMap, world_coord: Vector2, camera: ray.Camera2D) Vector2Int {
        var world_space = ray.GetScreenToWorld2D(ray.Vector2{ .x = world_coord.x, .y = world_coord.y }, camera);
        if (self.map_bounds.containsPoint(Vector2{ .x = world_space.x, .y = world_space.y }) == false) {
            return Vector2Int{
                .x = 0,
                .y = 0,
            };
        }
        const world_x: u32 = @intFromFloat(world_space.x);
        const world_y: u32 = @intFromFloat(world_space.y);
        return Vector2Int{
            .x = world_x / self.tile_size.x,
            .y = world_y / self.tile_size.y,
        };
    }

    fn update(self: *TileMap, mouse_state: MouseState, key_pressed: c_int, mouse_over_ui: bool, camera: ray.Camera2D, current_tile: u32, tileset: TileSet) void {
        self.active_layer = switch (key_pressed) {
            ray.KEY_KP_0 => 0,
            ray.KEY_KP_1 => 1,
            ray.KEY_KP_2 => 2,
            ray.KEY_KP_3 => 3,
            ray.KEY_KP_4 => 4,
            else => self.active_layer,
        };

        // Ignore Offscreen
        if (mouse_over_ui or
            !mouse_state.left_button.is_down or
            mouse_state.position.x < 0.0 or
            mouse_state.position.y < 0.0)
        {
            return;
        }

        var world_space = ray.GetScreenToWorld2D(ray.Vector2{ .x = mouse_state.position.x, .y = mouse_state.position.y }, camera);
        if (self.map_bounds.containsPoint(Vector2{ .x = world_space.x, .y = world_space.y }) == false) {
            return;
        }
        const ftile_x: f32 = @floatFromInt(self.tile_size.x);
        const ftile_y: f32 = @floatFromInt(self.tile_size.y);
        const tile_x: u32 = @intFromFloat(world_space.x / ftile_x);
        const tile_y: u32 = @intFromFloat(world_space.y / ftile_y);

        const tile_idx: u32 = tile_y * self.tile_dims.x + tile_x;

        var tile: *Tile = &self.layers.items[self.active_layer].tiles.items[tile_idx];
        if (tile.occupied and tile.tileset_idx == current_tile) return;
        tile.tileset_idx = current_tile;
        tile.occupied = true;

        self.layers.items[self.active_layer].redraw(tileset);
    }

    fn draw(self: *TileMap) void {
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
        for (self.layers.items) |*layer| {
            layer.draw();
        }
    }

    fn deinit(self: *TileMap) void {
        for (self.layers.items) |*layer| {
            layer.deinit();
        }
        self.layers.deinit();
    }
};

pub fn main() !void {
    // Rewrite considerations:
    // use more floats! The type conversions are super annoying
    // Do something about draw order? More generalized solution for overlapping?
    const width: u32 = 1440;
    const height: u32 = 960;
    const tile_width = 24;
    const tile_height = 24;

    // In Tiles
    const tilemap_dims = Vector2Int{ .x = width * 5, .y = height * 5 };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    var allocator = gpa.allocator();

    //ray.SetConfigFlags(ray.FLAG_VSYNC_HINT);
    ray.InitWindow(width, height, "zig raylib example");
    defer ray.CloseWindow();
    ray.SetTargetFPS(144);
    var display_text: [20]u8 = undefined;
    var layer_text: [20]u8 = undefined;
    var coord_text: [20]u8 = undefined;

    var tilemap = try TileMap.init(
        allocator,
        tilemap_dims,
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
    camera.offset = ray.Vector2{ .x = width / 2, .y = height / 2 };
    camera.rotation = 0.0;
    camera.zoom = 1.0;
    const movement_speed: f32 = 500.0;
    while (!ray.WindowShouldClose()) {
        // Get Input
        var mouse_state = MouseState.getState();
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

        var tile_coord = tilemap.worldToTileCoords(mouse_state.position, camera);
        const coord_output = try std.fmt.bufPrint(&coord_text, "({d},{d})", .{ tile_coord.x, tile_coord.y });
        coord_text[coord_output.len] = 0;

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

        var mouse_over_ui = tileset_picker.mouseOverPicker(mouse_state.position);
        tilemap.update(
            mouse_state,
            key_pressed,
            mouse_over_ui,
            camera,
            tileset_picker.current_tile,
            tileset,
        );

        if (tileset_picker.visible) {
            tileset_picker.update(mouse_state);
        }

        ray.BeginDrawing();
        ray.ClearBackground(ray.BLUE);

        ray.BeginMode2D(camera);
        tilemap.draw();
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
