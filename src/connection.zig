const std = @import("std");
const Client = @import("client.zig").Client;
const client = @import("client.zig").client;
const common = @import("common.zig");
const Stream = @import("./stream.zig");

const net = std.net;
const mem = std.mem;
const io = std.io;
const Opcode = common.Opcode;
const Message = common.Message;

const READ_BUFFER_SIZE: usize = 1024 * 8;
const WRITE_BUFFER_SIZE: usize = 1024 * 4;

/// This is the direct implementation of ws over regular net.Stream.
/// The Connection object will always use the current Stream implementation of net namespace.
pub const Connection = struct {
    underlying_stream: Stream,
    ws_client: *WsClient,
    buffered_reader: BufferedReader,
    headers: std.StringHashMapUnmanaged([]const u8),

    /// general types
    const WsClient = Client(Reader, Writer, READ_BUFFER_SIZE, WRITE_BUFFER_SIZE);
    const BufferedReader = io.BufferedReader(4096, Stream.Reader);
    const Reader = BufferedReader.Reader;
    const Writer = Stream.Writer;

    pub fn init(
        allocator: mem.Allocator,
        underlying_stream: Stream,
        uri: std.Uri,
        extra_headers: []const common.HttpHeader,
    ) !Connection {
        var owned_stream = underlying_stream;
        var buffered_reader = BufferedReader{ .unbuffered_reader = owned_stream.reader() };
        const writer = owned_stream.writer();

        const ws_client = try allocator.create(WsClient);
        errdefer allocator.destroy(ws_client);

        ws_client.* = client(
            buffered_reader.reader(),
            writer,
            READ_BUFFER_SIZE,
            WRITE_BUFFER_SIZE,
        );

        var self = Connection{
            .underlying_stream = owned_stream,
            .ws_client = ws_client,
            .buffered_reader = buffered_reader,
            .headers = .{},
        };

        try self.ws_client.handshake(allocator, uri, extra_headers, &self.headers);
        return self;
    }

    pub fn deinit(self: *Connection, allocator: mem.Allocator) void {
        defer allocator.destroy(self.ws_client);
        self.ws_client.deinit(allocator, &self.headers);
        self.underlying_stream.close();
    }

    /// Send a WebSocket message to the server.
    /// The `opcode` field can be text, binary, ping, pong or close.
    /// In order to send continuation frames or streaming messages, check out `stream` function.
    pub fn send(self: Connection, opcode: Opcode, data: []const u8) !void {
        return self.ws_client.send(opcode, data);
    }

    /// Send a ping message to the server.
    pub fn ping(self: Connection) !void {
        return self.send(.ping, "");
    }

    /// Send a pong message to the server.
    pub fn pong(self: Connection) !void {
        return self.send(.pong, "");
    }

    /// Send a close message to the server.
    pub fn close(self: Connection) !void {
        return self.ws_client.close();
    }

    /// TODO: Add usage example
    /// Send send continuation frames or streaming messages to the server.
    pub fn stream(self: Connection, opcode: Opcode, payload: ?[]const u8) !void {
        return self.ws_client.stream(opcode, payload);
    }

    /// Receive a message from the server.
    pub fn receive(self: Connection) !Message {
        return self.ws_client.receive();
    }
};
