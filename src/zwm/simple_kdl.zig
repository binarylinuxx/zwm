const std = @import("std");

// Simple KDL parser - only handles what we need for zwm config
// Supports:
// - Nodes with names
// - String arguments (quoted)
// - Number arguments (int/float)
// - Children blocks {}
// - Comments //

pub const Node = struct {
    name: []const u8,
    args: std.ArrayList([]const u8),
    children: std.ArrayList(Node),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Node) void {
        for (self.args.items) |arg| {
            self.allocator.free(arg);
        }
        self.args.deinit();

        for (self.children.items) |*child| {
            child.deinit();
        }
        self.children.deinit();

        self.allocator.free(self.name);
    }

    pub fn getArg(self: *const Node, index: usize) ?[]const u8 {
        if (index >= self.args.items.len) return null;
        return self.args.items[index];
    }

    pub fn findChild(self: *const Node, name: []const u8) ?*const Node {
        for (self.children.items) |*child| {
            if (std.mem.eql(u8, child.name, name)) return child;
        }
        return null;
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    content: []const u8,
    pos: usize,

    pub fn init(allocator: std.mem.Allocator, content: []const u8) Parser {
        return .{
            .allocator = allocator,
            .content = content,
            .pos = 0,
        };
    }

    pub fn parse(self: *Parser) std.mem.Allocator.Error!std.ArrayList(Node) {
        var nodes = std.ArrayList(Node).init(self.allocator);

        while (self.pos < self.content.len) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.content.len) break;

            const node = try self.parseNode();
            try nodes.append(node);
        }

        return nodes;
    }

    fn parseNode(self: *Parser) std.mem.Allocator.Error!Node {
        // Parse node name
        const name = try self.parseIdentifier();

        var node = Node{
            .name = name,
            .args = std.ArrayList([]const u8).init(self.allocator),
            .children = std.ArrayList(Node).init(self.allocator),
            .allocator = self.allocator,
        };

        // Parse arguments until we hit { or newline
        while (self.pos < self.content.len) {
            self.skipSpacesAndTabs();  // Only skip spaces/tabs, not newlines!
            if (self.pos >= self.content.len) break;

            const c = self.content[self.pos];

            // Children block
            if (c == '{') {
                self.pos += 1;
                node.children = try self.parseChildren();
                self.skipWhitespace();
                if (self.pos < self.content.len and self.content[self.pos] == '}') {
                    self.pos += 1;
                }
                // Skip trailing whitespace/newline after children block
                self.skipWhitespace();
                if (self.pos < self.content.len and (self.content[self.pos] == '\n' or self.content[self.pos] == '\r')) {
                    self.pos += 1;
                    if (self.pos < self.content.len and self.content[self.pos] == '\n') {
                        self.pos += 1; // Handle \r\n
                    }
                }
                return node;
            }

            // End of node
            if (c == '\n' or c == '\r') {
                break;
            }

            // String argument
            if (c == '"') {
                const arg = try self.parseString();
                try node.args.append(arg);
            }
            // Number or identifier argument
            else if (std.ascii.isAlphanumeric(c) or c == '-' or c == '.') {
                const arg = try self.parseValue();
                try node.args.append(arg);
            }
            else {
                self.pos += 1; // Skip unknown char
            }
        }

        return node;
    }

    fn parseChildren(self: *Parser) std.mem.Allocator.Error!std.ArrayList(Node) {
        var children = std.ArrayList(Node).init(self.allocator);

        while (self.pos < self.content.len) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.content.len) break;

            if (self.content[self.pos] == '}') {
                break;
            }

            const child = try self.parseNode();
            try children.append(child);
        }

        return children;
    }

    fn parseIdentifier(self: *Parser) std.mem.Allocator.Error![]const u8 {
        const start = self.pos;

        while (self.pos < self.content.len) {
            const c = self.content[self.pos];
            // Allow alphanumeric, -, +, and _
            if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '+') {
                self.pos += 1;
            } else {
                break;
            }
        }

        const ident = self.content[start..self.pos];
        return try self.allocator.dupe(u8, ident);
    }

    fn parseString(self: *Parser) std.mem.Allocator.Error![]const u8 {
        self.pos += 1; // Skip opening "
        const start = self.pos;

        while (self.pos < self.content.len and self.content[self.pos] != '"') {
            // Simple escape handling
            if (self.content[self.pos] == '\\' and self.pos + 1 < self.content.len) {
                self.pos += 2;
            } else {
                self.pos += 1;
            }
        }

        const str = self.content[start..self.pos];
        if (self.pos < self.content.len) self.pos += 1; // Skip closing "

        return try self.allocator.dupe(u8, str);
    }

    fn parseValue(self: *Parser) std.mem.Allocator.Error![]const u8 {
        const start = self.pos;

        while (self.pos < self.content.len) {
            const c = self.content[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '-' or c == '.' or c == '_') {
                self.pos += 1;
            } else {
                break;
            }
        }

        const val = self.content[start..self.pos];
        return try self.allocator.dupe(u8, val);
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.content.len) {
            const c = self.content[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
            } else {
                break;
            }
        }
    }

    fn skipSpacesAndTabs(self: *Parser) void {
        while (self.pos < self.content.len) {
            const c = self.content[self.pos];
            if (c == ' ' or c == '\t') {
                self.pos += 1;
            } else {
                break;
            }
        }
    }

    fn skipWhitespaceAndComments(self: *Parser) void {
        while (self.pos < self.content.len) {
            self.skipWhitespace();

            // Skip // comments
            if (self.pos + 1 < self.content.len and
                self.content[self.pos] == '/' and
                self.content[self.pos + 1] == '/') {
                // Skip until end of line
                while (self.pos < self.content.len and
                       self.content[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }
};

pub fn freeNodes(nodes: *std.ArrayList(Node)) void {
    for (nodes.items) |*node| {
        node.deinit();
    }
    nodes.deinit();
}
