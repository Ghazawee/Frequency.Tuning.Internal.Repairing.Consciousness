ft_irc Server - Usage Examples
==============================

## Starting the Server
```bash
./ircserv 6667 mypassword
```
- Port: 6667 (standard IRC port)
- Password: "mypassword" (change as needed)

## Connecting with IRC Clients

### Using HexChat
1. Add new network: localhost/6667
2. Set server password: mypassword
3. Connect and join channels

### Using netcat (for testing)
```bash
nc localhost 6667
PASS mypassword
NICK yourname
USER yourname 0 * :Your Real Name
JOIN #general
PRIVMSG #general :Hello everyone!
```

## Example Session
```
PASS mypassword                    # Authenticate
NICK alice                         # Set nickname
USER alice 0 * :Alice Smith        # Register user
JOIN #general                      # Join channel
PRIVMSG #general :Hello!           # Send message
TOPIC #general :Welcome to chat    # Set topic (if operator)
MODE #general +t                   # Set topic protection
INVITE bob #general                # Invite user
KICK bob #general :Spam            # Kick user (if operator)
PART #general :Goodbye             # Leave channel
QUIT :Session ended                # Disconnect
```

## Channel Modes
- +i : Invite-only channel
- +t : Topic protection (only operators can change)
- +k : Channel key/password required
- +o : Give operator status to user
- +l : Set user limit

Examples:
```
MODE #channel +i              # Make invite-only
MODE #channel +k secretpass   # Set channel password
MODE #channel +l 50           # Limit to 50 users
MODE #channel +o alice        # Make alice an operator
```

## Testing
Run the comprehensive test suite:
```bash
./run_tests.sh
```

This will test all IRC functionality including:
- Authentication
- Channel operations
- Messaging
- Modes
- Multiple clients
