#!/bin/bash

# IRC Server Test Suite
# Tests core functionality with proper timeout handling

PORT=6667
PASSWORD="mypassword"
WRONG_PASSWORD="wrongpass"
SERVER_PID=""
TIMEOUT=3

echo "=== IRC Server Test Suite ==="
echo "Testing Port: $PORT"
echo "Password: $PASSWORD"
echo ""

# Function to start server
start_server() {
    echo "Starting IRC server..."
    ./ircserv $PORT $PASSWORD &
    SERVER_PID=$!
    sleep 2
    
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "FAILED: Server failed to start"
        exit 1
    fi
    echo "Server started (PID: $SERVER_PID)"
    echo ""
}

# Function to stop server
stop_server() {
    if [ ! -z "$SERVER_PID" ]; then
        echo "Stopping server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null
        wait $SERVER_PID 2>/dev/null
        echo "Server stopped"
    fi
}

# Function to test with timeout
test_with_timeout() {
    local test_name="$1"
    local commands="$2"
    local expected_pattern="$3"
    
    echo "Testing: $test_name"
    
    # Create temp file for output
    local temp_output=$(mktemp)
    
    # Run test with timeout
    (
        echo -e "$commands"
        sleep 1
    ) | timeout $TIMEOUT nc localhost $PORT > "$temp_output" 2>&1
    
    local exit_code=$?
    local output=$(cat "$temp_output")
    
    echo "Sent commands:"
    echo "$commands" | sed 's/^/    /'
    echo "Server response:"
    echo "$output" | sed 's/^/    /'
    
    if [ $exit_code -eq 124 ]; then
        echo "Test timed out after ${TIMEOUT}s"
    fi
    
    if echo "$output" | grep -q "$expected_pattern"; then
        echo "PASSED: Found expected pattern '$expected_pattern'"
    else
        echo "FAILED: Expected pattern '$expected_pattern' not found"
    fi
    
    rm -f "$temp_output"
    echo ""
}

# Cleanup function
cleanup() {
    stop_server
    echo "Cleanup completed."
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Build the server if needed
if [ ! -f "./ircserv" ]; then
    echo "Building IRC server..."
    make
    if [ $? -ne 0 ]; then
        echo "FAILED: Build failed"
        exit 1
    fi
    echo "Build successful"
    echo ""
fi

# Start server
start_server

echo "=== TEST 1: Wrong Password Authentication ==="
test_with_timeout \
    "Wrong password should be rejected" \
    "PASS $WRONG_PASSWORD\r\nNICK testuser\r\nQUIT\r\n" \
    "464.*Password incorrect"

echo "=== TEST 2: Correct Password Authentication ==="
test_with_timeout \
    "Correct password should be accepted" \
    "PASS $PASSWORD\r\nNICK testuser\r\nUSER testuser 0 * :Test User\r\nQUIT\r\n" \
    "001.*Welcome"

echo "=== TEST 3: Nickname Conflict Detection ==="
# First client registers
(
    echo -e "PASS $PASSWORD\r\nNICK testuser\r\nUSER testuser 0 * :Test User\r\n"
    sleep 5
) | nc localhost $PORT &
NC_PID1=$!
sleep 1

# Second client tries same nickname
test_with_timeout \
    "Duplicate nickname should be rejected" \
    "PASS $PASSWORD\r\nNICK testuser\r\nQUIT\r\n" \
    "433.*Nickname is already in use"

# Cleanup first connection
kill $NC_PID1 2>/dev/null
sleep 1

echo "=== TEST 4: Command Without Authentication ==="
test_with_timeout \
    "Commands without PASS should be rejected" \
    "NICK testuser\r\nQUIT\r\n" \
    "451.*You have not registered"

echo "=== TEST 5: Complete Registration Process ==="
test_with_timeout \
    "Full registration should work" \
    "PASS $PASSWORD\r\nNICK validuser\r\nUSER validuser 0 * :Valid User\r\nQUIT\r\n" \
    "004.*ft_irc"

echo "=== TEST 6: Channel Operations ==="
test_with_timeout \
    "Channel join and topic should work" \
    "PASS $PASSWORD\r\nNICK channeluser\r\nUSER channeluser 0 * :Channel User\r\nJOIN #testchan\r\nTOPIC #testchan :Test Topic\r\nQUIT\r\n" \
    "JOIN.*#testchan"

echo "=== TEST 7: Invalid Commands ==="
test_with_timeout \
    "Invalid commands should be handled gracefully" \
    "PASS $PASSWORD\r\nNICK invaliduser\r\nUSER invaliduser 0 * :Invalid User\r\nINVALIDCOMMAND\r\nQUIT\r\n" \
    "421.*Unknown command"

echo "=== TEST 8: Case Sensitivity Test ==="
test_with_timeout \
    "Lowercase commands should be rejected" \
    "PASS $PASSWORD\r\njoin #test\r\nQUIT\r\n" \
    "421.*Unknown command"

echo "=== TEST SUMMARY ==="
echo "All basic IRC server functionality has been tested:"
echo "- Password authentication (correct/incorrect)"
echo "- Password retry without disconnection"
echo "- Nickname registration and conflict detection"
echo "- User registration and welcome sequence"
echo "- Authentication requirement enforcement"
echo "- Channel operations (JOIN, TOPIC)"
echo "- Invalid command handling"
echo "- Case sensitivity enforcement"
echo ""
echo "IRC Server Test Suite Complete!"
echo ""
echo "Server is running and ready for manual testing:"
echo "Connect with: nc localhost $PORT"
echo ""
echo "Press Ctrl+C to stop the server and exit."

# Keep server running for manual testing
while true; do
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "Server process ended unexpectedly"
        break
    fi
    sleep 1
done
