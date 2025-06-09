# ft_irc - IRC Server Implementation

A fully functional IRC server implementation in C++98 for the 42 school project. This server handles multiple clients simultaneously using non-blocking I/O with `poll()` and implements core IRC commands and channel operations.

## 🚀 Features

### Core Functionality
- **Multi-client support** with non-blocking I/O using `poll()`
- **Password authentication** for server access
- **User registration** (NICK/USER commands)
- **Channel operations** (JOIN/PART/KICK/INVITE)
- **Message handling** (PRIVMSG to users and channels)
- **Channel management** (TOPIC/MODE commands)
- **Graceful shutdown** with SIGINT handling

### IRC Commands Implemented
- `PASS` - Server password authentication
- `NICK` - Set or change nickname
- `USER` - User registration
- `JOIN` - Join channels
- `PART` - Leave channels
- `PRIVMSG` - Send messages to users/channels
- `KICK` - Remove users from channels (operator only)
- `INVITE` - Invite users to channels (operator only)
- `TOPIC` - View/set channel topic
- `MODE` - Set channel modes (i/t/k/o/l)
- `QUIT` - Disconnect from server

### Channel Features
- **Channel operators** with special privileges
- **Channel modes**: invite-only (i), topic restriction (t), key protection (k), user limit (l)
- **User limit enforcement**
- **Invite-only channels**
- **Key-protected channels**

## 🏗️ Architecture

### Class Structure
```
Server      - Main server class, handles socket operations and client management
Client      - Represents connected users with authentication state
Channel     - Manages IRC channels with operators and modes
Parser      - Parses and executes IRC commands
Utils       - Utility functions for string manipulation and IRC formatting
```

### File Organization
```
ircserv.hpp     - Main header with includes and forward declarations
main.cpp        - Entry point and argument parsing
Server.hpp/.cpp - Server implementation
Client.hpp/.cpp - Client management
Channel.hpp/.cpp- Channel operations
Parser.hpp/.cpp - Command parsing and execution
Utils.hpp/.cpp  - Utility functions
Makefile        - Build configuration
```

## 🛠️ Building and Running

### Requirements
- C++ compiler with C++98 support
- POSIX-compliant system (Linux/macOS)
- Make utility

### Compilation
```bash
make                # Build the server
make clean          # Remove object files
make fclean         # Remove all generated files
make re             # Clean and rebuild
```

### Usage
```bash
./ircserv <port> <password>
```

**Parameters:**
- `port`: Port number for the server (1024-65535)
- `password`: Server password for client authentication

**Example:**
```bash
./ircserv 6667 mypassword
```

## 🧪 Testing

### Basic Test
```bash
# Connect with netcat
echo -e "PASS mypassword\rNICK testuser\rUSER testuser 0 * :Test User\r" | nc localhost 6667
```

### Full Feature Test
```bash
# Test script provided
chmod +x test_comprehensive.sh
./test_comprehensive.sh
```

### IRC Client Testing
The server is compatible with standard IRC clients like:
- HexChat
- IRCCloud
- WeeChat
- irssi

## 📚 Educational Aspects

### C++ Concepts Demonstrated
- **Object-Oriented Programming**: Classes, encapsulation, inheritance
- **Memory Management**: RAII, proper cleanup in destructors
- **STL Containers**: `std::vector`, `std::map`, `std::string`
- **Exception Safety**: Resource management and error handling
- **Static Members**: Class-level data and functions

### Networking Concepts
- **Socket Programming**: TCP server sockets, client connections
- **Non-blocking I/O**: `fcntl()` with `O_NONBLOCK`
- **I/O Multiplexing**: `poll()` for handling multiple clients
- **Network Byte Order**: `htons()`, `ntohs()` for portability

### System Programming
- **Signal Handling**: Graceful shutdown with SIGINT
- **Process Management**: Proper resource cleanup
- **Error Handling**: Comprehensive error checking with `errno`

## 🔧 Implementation Details

### Socket Management
```cpp
// Non-blocking socket setup
int flags = fcntl(socket_fd, F_GETFL, 0);
fcntl(socket_fd, F_SETFL, flags | O_NONBLOCK);

// Reuse address option
int opt = 1;
setsockopt(socket_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
```

### Poll Loop
```cpp
// Main event loop with poll()
std::vector<pollfd> pollFds;
// ... setup pollFds ...
int result = poll(&pollFds[0], pollFds.size(), 1000);
```

### Command Parsing
```cpp
// IRC message format: [:prefix] COMMAND [params] [:trailing]
IRCCommand parseCommand(const std::string& message);
```

### Memory Safety
- RAII principles for resource management
- Proper cleanup in destructors
- No memory leaks or dangling pointers

## 🐛 Debugging

### Common Issues
1. **Port already in use**: Choose a different port or wait for timeout
2. **Permission denied**: Use ports > 1024 for non-root users
3. **Connection refused**: Check firewall settings

### Debug Mode
Uncomment debug lines in `Server.cpp` for verbose output:
```cpp
std::cout << "Processing command: '" << command << "'" << std::endl;
```

## 📖 IRC Protocol Reference

This implementation follows RFC 1459 (Internet Relay Chat Protocol) with focus on:
- Message format and parsing
- Numeric reply codes
- Channel naming conventions
- User mode handling

### Numeric Replies
- 001-004: Welcome messages
- 324: Channel mode is
- 332: Topic reply
- 353-366: Names reply
- 401-482: Error codes

## 🎯 42 School Requirements Compliance

- ✅ C++98 standard compliance
- ✅ Non-blocking I/O with `poll()`
- ✅ Multiple client handling
- ✅ IRC command implementation
- ✅ Channel operations
- ✅ Error handling
- ✅ Memory management
- ✅ No forbidden functions used

## 🤝 Contributing

This is an educational project for 42 school. The code includes extensive comments explaining C++ concepts, networking principles, and IRC protocol details for learning purposes.

## 📝 License

This project is created for educational purposes as part of the 42 school curriculum.

---

**Author**: Created for 42 school ft_irc project  
**Date**: June 2025  
**Standard**: C++98  
**Protocol**: IRC (RFC 1459)
