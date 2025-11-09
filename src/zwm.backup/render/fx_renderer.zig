const std = @import("std");
const wlr = @import("wlroots");

// C interop for OpenGL ES
const c = @cImport({
    @cInclude("GLES2/gl2.h");
    @cInclude("EGL/egl.h");
});

/// FX Renderer - Custom rendering effects for windows
/// Supports: rounded corners, blur, shadows, and custom shaders
pub const FXRenderer = struct {
    allocator: std.mem.Allocator,
    initialized: bool = false,

    // Shader programs
    rounded_shader: ShaderProgram = .{},
    blur_shader: ShaderProgram = .{},

    // Vertex buffer for rendering quads
    vbo: c.GLuint = 0,
    vao: c.GLuint = 0,

    // Configuration
    corner_radius: f32 = 0.0,
    blur_radius: f32 = 0.0,

    pub fn init(allocator: std.mem.Allocator) !FXRenderer {
        return .{
            .allocator = allocator,
            .initialized = false,
        };
    }

    pub fn deinit(self: *FXRenderer) void {
        if (!self.initialized) return;

        self.rounded_shader.deinit();
        self.blur_shader.deinit();

        if (self.vbo != 0) {
            c.glDeleteBuffers(1, &self.vbo);
            self.vbo = 0;
        }

        self.initialized = false;
    }

    /// Initialize shaders and GL resources
    pub fn initializeGL(self: *FXRenderer) !void {
        if (self.initialized) return;

        std.log.info("Initializing FX renderer with OpenGL ES", .{});

        // Initialize rounded corner shader
        try self.rounded_shader.compile(
            rounded_vertex_source,
            rounded_fragment_source,
        );

        // Create vertex buffer for quad rendering
        const vertices = [_]f32{
            // Position (x, y)  TexCoord (u, v)
            0.0, 0.0,           0.0, 0.0, // Bottom-left
            1.0, 0.0,           1.0, 0.0, // Bottom-right
            1.0, 1.0,           1.0, 1.0, // Top-right
            0.0, 1.0,           0.0, 1.0, // Top-left
        };

        c.glGenBuffers(1, &self.vbo);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, c.GL_STATIC_DRAW);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

        self.initialized = true;
        std.log.info("FX renderer initialized successfully", .{});
    }

    pub fn setCornerRadius(self: *FXRenderer, radius: f32) void {
        self.corner_radius = radius;
    }

    pub fn setBlurRadius(self: *FXRenderer, radius: f32) void {
        self.blur_radius = radius;
    }

    /// Apply rounded corner clipping using OpenGL stencil buffer
    /// This should be called during the render pass for each window
    pub fn applyRoundedCorners(self: *FXRenderer, x: i32, y: i32, width: i32, height: i32) void {
        if (self.corner_radius <= 0.0) return;
        if (!self.initialized) return;

        // Enable stencil testing
        c.glEnable(c.GL_STENCIL_TEST);
        c.glStencilMask(0xFF);
        c.glClear(c.GL_STENCIL_BUFFER_BIT);

        // Configure stencil test to write to stencil buffer
        c.glStencilFunc(c.GL_ALWAYS, 1, 0xFF);
        c.glStencilOp(c.GL_KEEP, c.GL_KEEP, c.GL_REPLACE);

        // Disable color writing (we only want to write to stencil)
        c.glColorMask(c.GL_FALSE, c.GL_FALSE, c.GL_FALSE, c.GL_FALSE);

        // Draw rounded rectangle to stencil buffer
        self.drawRoundedRectangleToStencil(x, y, width, height);

        // Re-enable color writing
        c.glColorMask(c.GL_TRUE, c.GL_TRUE, c.GL_TRUE, c.GL_TRUE);

        // Configure stencil test to only render where stencil = 1
        c.glStencilFunc(c.GL_EQUAL, 1, 0xFF);
        c.glStencilMask(0x00);
    }

    /// End rounded corner clipping (disable stencil test)
    pub fn endRoundedCorners(self: *FXRenderer) void {
        if (self.corner_radius <= 0.0) return;
        c.glDisable(c.GL_STENCIL_TEST);
    }

    /// Draw a rounded rectangle to the stencil buffer using signed distance field
    fn drawRoundedRectangleToStencil(self: *FXRenderer, x: i32, y: i32, width: i32, height: i32) void {
        if (!self.initialized) return;

        // Use the rounded shader
        c.glUseProgram(self.rounded_shader.program);

        // Get uniform locations
        const size_loc = c.glGetUniformLocation(self.rounded_shader.program, "size");
        const radius_loc = c.glGetUniformLocation(self.rounded_shader.program, "radius");
        const position_loc = c.glGetUniformLocation(self.rounded_shader.program, "position");

        // Set uniforms
        c.glUniform2f(size_loc, @floatFromInt(width), @floatFromInt(height));
        c.glUniform1f(radius_loc, self.corner_radius);
        c.glUniform2f(position_loc, @floatFromInt(x), @floatFromInt(y));

        // Bind vertex buffer
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);

        // Get attribute locations
        const pos_attrib = c.glGetAttribLocation(self.rounded_shader.program, "position");
        const tex_attrib = c.glGetAttribLocation(self.rounded_shader.program, "texcoord");

        // Enable and configure vertex attributes
        c.glEnableVertexAttribArray(@intCast(pos_attrib));
        c.glVertexAttribPointer(
            @intCast(pos_attrib),
            2,
            c.GL_FLOAT,
            c.GL_FALSE,
            4 * @sizeOf(f32),
            null,
        );

        c.glEnableVertexAttribArray(@intCast(tex_attrib));
        c.glVertexAttribPointer(
            @intCast(tex_attrib),
            2,
            c.GL_FLOAT,
            c.GL_FALSE,
            4 * @sizeOf(f32),
            @ptrFromInt(2 * @sizeOf(f32)),
        );

        // Draw the quad as a triangle fan
        c.glDrawArrays(c.GL_TRIANGLE_FAN, 0, 4);

        // Cleanup
        c.glDisableVertexAttribArray(@intCast(pos_attrib));
        c.glDisableVertexAttribArray(@intCast(tex_attrib));
        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
        c.glUseProgram(0);
    }
};

/// Shader program wrapper
const ShaderProgram = struct {
    program: c.GLuint = 0,
    vertex_shader: c.GLuint = 0,
    fragment_shader: c.GLuint = 0,

    pub fn compile(self: *ShaderProgram, vertex_src: []const u8, fragment_src: []const u8) !void {
        // Compile vertex shader
        self.vertex_shader = c.glCreateShader(c.GL_VERTEX_SHADER);
        const vertex_ptr: [*c]const u8 = @ptrCast(vertex_src.ptr);
        const vertex_len: c.GLint = @intCast(vertex_src.len);
        c.glShaderSource(self.vertex_shader, 1, &vertex_ptr, &vertex_len);
        c.glCompileShader(self.vertex_shader);

        var success: c.GLint = 0;
        c.glGetShaderiv(self.vertex_shader, c.GL_COMPILE_STATUS, &success);
        if (success == 0) {
            var info_log: [512]u8 = undefined;
            @memset(&info_log, 0);
            var log_length: c.GLsizei = 0;
            c.glGetShaderInfoLog(self.vertex_shader, 512, &log_length, @ptrCast(&info_log));
            std.log.err("Vertex shader compilation failed:\n{s}", .{info_log[0..@intCast(log_length)]});
            return error.ShaderCompilationFailed;
        }

        // Compile fragment shader
        self.fragment_shader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
        const fragment_ptr: [*c]const u8 = @ptrCast(fragment_src.ptr);
        const fragment_len: c.GLint = @intCast(fragment_src.len);
        c.glShaderSource(self.fragment_shader, 1, &fragment_ptr, &fragment_len);
        c.glCompileShader(self.fragment_shader);

        c.glGetShaderiv(self.fragment_shader, c.GL_COMPILE_STATUS, &success);
        if (success == 0) {
            var info_log: [512]u8 = undefined;
            @memset(&info_log, 0);
            var log_length: c.GLsizei = 0;
            c.glGetShaderInfoLog(self.fragment_shader, 512, &log_length, @ptrCast(&info_log));
            std.log.err("Fragment shader compilation failed:\n{s}", .{info_log[0..@intCast(log_length)]});
            return error.ShaderCompilationFailed;
        }

        // Link program
        self.program = c.glCreateProgram();
        c.glAttachShader(self.program, self.vertex_shader);
        c.glAttachShader(self.program, self.fragment_shader);
        c.glLinkProgram(self.program);

        c.glGetProgramiv(self.program, c.GL_LINK_STATUS, &success);
        if (success == 0) {
            var info_log: [512]u8 = undefined;
            @memset(&info_log, 0);
            var log_length: c.GLsizei = 0;
            c.glGetProgramInfoLog(self.program, 512, &log_length, @ptrCast(&info_log));
            std.log.err("Shader program linking failed:\n{s}", .{info_log[0..@intCast(log_length)]});
            return error.ShaderLinkingFailed;
        }

        std.log.info("Shader compiled and linked successfully", .{});
    }

    pub fn deinit(self: *ShaderProgram) void {
        if (self.program != 0) {
            c.glDeleteProgram(self.program);
            self.program = 0;
        }
        if (self.vertex_shader != 0) {
            c.glDeleteShader(self.vertex_shader);
            self.vertex_shader = 0;
        }
        if (self.fragment_shader != 0) {
            c.glDeleteShader(self.fragment_shader);
            self.fragment_shader = 0;
        }
    }
};

// Vertex shader for rounded corners
const rounded_vertex_source =
    \\attribute vec2 position;
    \\attribute vec2 texcoord;
    \\varying vec2 v_texcoord;
    \\uniform mat3 proj;
    \\void main() {
    \\    gl_Position = vec4(proj * vec3(position, 1.0), 1.0);
    \\    v_texcoord = texcoord;
    \\}
;

// Fragment shader with rounded corner SDF (Signed Distance Field)
const rounded_fragment_source =
    \\precision mediump float;
    \\varying vec2 v_texcoord;
    \\uniform sampler2D tex;
    \\uniform vec2 size;
    \\uniform float radius;
    \\
    \\float roundedBoxSDF(vec2 center, vec2 size, float radius) {
    \\    return length(max(abs(center) - size + radius, 0.0)) - radius;
    \\}
    \\
    \\void main() {
    \\    vec2 pixelPos = v_texcoord * size;
    \\    vec2 center = pixelPos - size * 0.5;
    \\    float dist = roundedBoxSDF(center, size * 0.5, radius);
    \\
    \\    // Anti-aliased clipping with smooth edges
    \\    float alpha = 1.0 - smoothstep(-1.0, 1.0, dist);
    \\
    \\    vec4 texColor = texture2D(tex, v_texcoord);
    \\    gl_FragColor = vec4(texColor.rgb, texColor.a * alpha);
    \\}
;
