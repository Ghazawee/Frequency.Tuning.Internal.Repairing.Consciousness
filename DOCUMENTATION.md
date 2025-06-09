# ft_irc - IRC Server Implementation

## Overview
A complete IRC server implementation in C++98 that follows RFC 1459 standards. The server supports multiple concurrent clients using non-blocking I/O and implements all essential IRC commands.

## Features

### Core Functionality
- Multi-client support with non-blocking I/O using poll()
- Password authentication with retry capability
- User registration (NICK/USER commands)
- Channel operations (JOIN/PART/KICK/INVITE)
- Message handling (PRIVMSG to users and channels)
- Channel management (TOPIC/MODE commands)
- Graceful shutdown with SIGINT handling

### Security Features
- Password protection (clients can retry wrong passwords)
- Input validation and buffer overflow protection
- Case-sensitive command parsing (commands must be UPPERCASE)
- Nickname conflict detection
- Authentication enforcement

### IRC Commands Implemented
- PASS - Server password authentication (case sensitive)
- NICK - Set or change nickname (case sensitive)
- USER - User registration (case sensitive)
- JOIN - Join channels (case sensitive)
- PART - Leave channels (case sensitive)
- PRIVMSG - Send messages to users/channels (case sensitive)
- KICK - Remove users from channels (operator only, case sensitive)
- INVITE - Invite users to channels (operator only, case sensitive)
- TOPIC - View/set channel topic (case sensitive)
- MODE - Set channel modes (i/t/k/o/l, case sensitive)
- QUIT - Disconnect from server (case sensitive)

## Usage

### Starting the Server
```bash
./ircserv <port> <password>
```

Example:
```bash
./ircserv 6667 mypassword
```

### Connecting with IRC Clients

#### Using netcat for testing
```bash
nc localhost 6667
PASS mypassword
NICK john
USER john 0 * :John Doe
JOIN #general
PRIVMSG #general :Hello everyone!
QUIT
```

#### Using IRC clients (HexChat, WeeChat, etc.)
1. Add new network: localhost/6667
2. Set server password: mypassword
3. Connect and join channels

## Architecture

### Core Components
- **Server**: Main server class handling network operations
- **Client**: Client state management and authentication
- **Parser**: IRC command parsing and execution
- **Channel**: Channel operations and user management
- **Utils**: Utility functions and IRC protocol helpers

### Network Layer
- Non-blocking I/O using poll() system call
- Efficient handling of multiple concurrent connections
- Proper socket management and cleanup

### Command Processing
- Case-sensitive command parsing (UPPERCASE only)
- RFC 1459 compliant message formatting
- Comprehensive error handling with proper IRC numeric replies

## Technical Details

### Authentication Flow
1. Client connects
2. PASS command required (can retry if wrong)
3. NICK command sets nickname (conflict detection)
4. USER command completes registration
5. Welcome sequence sent with command manual

### Channel Features
- Operator privileges (@)
- Channel modes (+i, +t, +k, +l, +o)
- Topic management
- User invite system
- Kick/ban functionality

### Error Handling
- Proper IRC numeric error codes
- Input validation and sanitization
- Buffer overflow protection
- Graceful client disconnection handling

## Server Output
Server displays all incoming commands directly without client identification for clean terminal output.

## Date and Time
Server creation time is displayed in human-readable format (YYYY-MM-DD HH:MM:SS) instead of Unix timestamp.

## Command Manual
Upon successful registration, clients receive a comprehensive manual of available commands via NOTICE messages.

## Testing
Use the provided test.sh script to verify all functionality:
```bash
./test.sh
```

## Security Considerations
- Commands are case-sensitive (must be UPPERCASE)
- Password authentication with retry capability
- Input validation prevents buffer overflow attacks
- Proper resource cleanup prevents memory leaks

## Compliance
This implementation follows RFC 1459 IRC protocol standards and passes all 42 school requirements for the ft_irc project.
