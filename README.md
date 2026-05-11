# ft_irc

![C++98](https://img.shields.io/badge/C%2B%2B-C%2B%2B98-blue)
![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20POSIX-lightgrey)
![Protocol](https://img.shields.io/badge/Protocol-IRC%20RFC%201459-orange)

## Overview

`ft_irc` is a C++98 IRC server that accepts multiple clients at once, manages channel state, and implements the core IRC workflow needed for the 42 school project.

It uses non-blocking sockets with `poll()`, password-based access, and buffered writes to handle partial sends safely.

## Table of Contents

- [Highlights](#highlights)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Usage Notes](#usage-notes)
- [Core Functional Coverage](#core-functional-coverage)
- [Feature Breakdown](#feature-breakdown)
- [Additional Notes](#additional-notes)

## Highlights

- Multiple clients handled through `poll()`
- Password-required server startup and client authentication
- Channel join, part, message, invite, kick, topic, and mode handling
- Channel modes `+i`, `+t`, `+k`, and `+l`
- Buffered outgoing messages for partial `send()` results
- Graceful shutdown on `SIGINT`
- IRC replies for user registration, channel membership, and error cases

## Architecture

The project is split into a small set of focused classes:

- `Server` manages sockets, client lifetimes, and the main event loop
- `Client` stores user state such as nickname, username, authentication, and buffers
- `Channel` tracks members, operators, topic, invitation state, and mode flags
- `Parser` interprets IRC commands and dispatches them to the correct handlers
- `Utils` contains helper functions for formatting, parsing, validation, and socket writes

The server accepts incoming connections, makes client sockets non-blocking, then uses `poll()` to read commands and flush pending output.

## Tech Stack

- Language: C++98
- Build system: Make
- Networking: POSIX sockets, `poll()`, `fcntl()`, `send()`, `recv()`
- Platform: Linux or any POSIX-like environment

## Project Structure

```text
main.cpp          - Program entry point and argument validation
Server.cpp/.hpp   - Socket setup, event loop, and client management
Client.cpp/.hpp   - Per-client state and output buffering
Channel.cpp/.hpp  - Channel membership, modes, topic, and invitations
Parser.cpp/.hpp   - IRC command parsing and handlers
Utils.cpp/.hpp    - Helper utilities and message formatting
ircserv.hpp       - Shared includes and forward declarations
Makefile          - Build rules
README.md         - Project overview and usage
DOCUMENTATION.md  - Additional implementation notes
USAGE.md          - Example usage
POLLOUT_IMPLEMENTATION.md - Notes on buffered output handling
```

## Getting Started

### Prerequisites

- A compiler with C++98 support
- `make`
- A POSIX environment such as Linux

### Build

```bash
make
```

### Clean

```bash
make clean
make fclean
make re
```

### Run

```bash
./ircserv <port> <password>
```

Example:

```bash
./ircserv 6667 mypassword
```

The port must be between `1024` and `65535`, and the password must be non-empty, under 50 characters, and contain no whitespace.

## Usage Notes

- Connect with an IRC client or a raw TCP client such as `nc`
- Send `PASS` before `NICK` and `USER`
- Commands are expected in standard IRC uppercase form
- The server replies with the usual IRC numeric responses for registration, names, topic, and error handling

Compatible IRC clients include irssi and HexChat.

Example session:

```bash
nc localhost 6667
PASS mypassword
NICK alice
USER alice 0 * :Alice
JOIN #general
PRIVMSG #general :Hello
```

## Core Functional Coverage

- `PASS` for server authentication
- `NICK` for nickname registration and changes
- `USER` for username and real name registration
- `JOIN` and `PART` for channel membership
- `PRIVMSG` for private and channel messages
- `KICK` for removing users from channels
- `INVITE` for invite-only workflows
- `TOPIC` for viewing and updating channel topics
- `MODE` for channel mode management
- `QUIT` for disconnecting cleanly
- `WHO` and `WHOIS` for user lookup support

## Feature Breakdown

### Channel management

- Tracks users and operators per channel
- Supports invite-only channels
- Supports topic-restricted channels
- Supports channel keys
- Supports user limits

### Connection handling

- Accepts multiple simultaneous clients
- Makes sockets non-blocking
- Ignores `SIGPIPE`
- Shuts down cleanly on `SIGINT`

### Output handling

- Buffers data when `send()` cannot write everything at once
- Flushes pending data when the socket becomes writable
- Preserves message ordering for partial sends

### Validation

- Validates port and password at startup
- Validates nicknames before registration
- Returns IRC-style errors for missing parameters, duplicate nicknames, and invalid targets

## Additional Notes

- This repository does not include bundled automated test scripts
- The implementation is intended for the 42 IRC project and follows the expected C++98 constraints
- Further details about buffering and protocol behavior are documented in the supplementary markdown files
