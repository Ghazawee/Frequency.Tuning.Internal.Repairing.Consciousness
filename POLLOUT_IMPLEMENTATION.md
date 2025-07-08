// Output Buffering and POLLOUT Implementation
// ==========================================
//
// This implementation adds robust output buffering and POLLOUT handling to the IRC server.
//
// Key Features:
// 1. When send() returns a partial send or EAGAIN/EWOULDBLOCK, the remaining data is buffered
// 2. POLLOUT is automatically enabled for clients with buffered output
// 3. The hasOutputBuffer() check prevents mixing partial messages
// 4. Buffered data is automatically sent when the socket becomes writable
//
// How it works:
// - Utils::sendToClient() checks if client has buffered output before sending
// - If send() fails or is partial, data is stored in client's output buffer
// - Server::run() enables POLLOUT for clients with buffered output
// - When POLLOUT is triggered, Server::flushClientOutputBuffer() sends buffered data
// - Process continues until all buffered data is sent
//
// Benefits:
// - Prevents message corruption from mixed partial sends
// - Handles network congestion gracefully
// - Maintains message ordering
// - Non-blocking operation
//
// Current behavior for failed sends:
// - sendToClient() returns false when buffering occurs
// - Calling code doesn't need to handle this - buffering is automatic
// - Messages will be delivered when the socket is ready
//
// For production use, you might want to add:
// - Maximum buffer size limits
// - Timeout handling for clients with persistent buffering
// - Bandwidth throttling
// - Buffer priority queuing
