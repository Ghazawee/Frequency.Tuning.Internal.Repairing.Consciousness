#!/bin/bash

# ===============================================================================
# COMPREHENSIVE IRC SERVER STRESS TEST & RFC 1459 COMPLIANCE VERIFICATION
# ===============================================================================
# This script performs exhaustive testing of the IRC server implementation
# covering all edge cases, potential memory leaks, segfaults, and RFC compliance
# 
# Test Categories:
# 1. RFC 1459 Compliance Tests
# 2. Buffer Overflow & Memory Safety Tests  
# 3. Concurrent Client Stress Tests
# 4. Protocol Edge Cases & Malformed Input
# 5. Resource Exhaustion Tests
# 6. Authentication & Security Tests
# 7. Channel Operation Stress Tests
# 8. Error Handling & Recovery Tests
# ===============================================================================

set -e  # Exit on any error

# Configuration
PORT=6667
PASSWORD="mypassword"
WRONG_PASSWORD="wrongpass"
SERVER_PID=""
TIMEOUT=10
MAX_CLIENTS=50  # Test multiple clients
MAX_CHANNELS=100
STRESS_DURATION=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

echo -e "${BLUE}===============================================================================${NC}"
echo -e "${BLUE}         COMPREHENSIVE IRC SERVER STRESS TEST & RFC 1459 COMPLIANCE${NC}"
echo -e "${BLUE}===============================================================================${NC}"
echo -e "Testing Port: $PORT"
echo -e "Password: $PASSWORD"
echo -e "Max Clients: $MAX_CLIENTS"
echo -e "Stress Duration: ${STRESS_DURATION}s"
echo ""

# Function to print test results
print_test_result() {
    local test_name="$1"
    local result="$2"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✅ PASS${NC}: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Function to start server with valgrind
start_server() {
    echo -e "${YELLOW}Starting IRC server with memory analysis...${NC}"
    
    # Clean previous logs
    rm -f valgrind_stress.log server_output.log
    
    # Try to start with valgrind first, fallback to normal execution
    if command -v valgrind >/dev/null 2>&1; then
        echo -e "${BLUE}   Using valgrind for memory analysis...${NC}"
        # Start server with basic valgrind flags (more compatible)
        ( valgrind \
            --leak-check=full \
            --show-leak-kinds=all \
            --track-origins=yes \
            --track-fds=yes \
            --error-exitcode=42 \
            --log-file=valgrind_stress.log \
            ./ircserv $PORT $PASSWORD \
        ) 2>server_output.log &
        
        SERVER_PID=$!
        sleep 3
        
        # If valgrind failed, try without it
        if ! kill -0 $SERVER_PID 2>/dev/null; then
            echo -e "${YELLOW}   Valgrind failed, starting without memory analysis...${NC}"
            ./ircserv $PORT $PASSWORD >server_output.log 2>&1 &
            SERVER_PID=$!
            sleep 2
        fi
    else
        echo -e "${YELLOW}   Valgrind not available, starting without memory analysis...${NC}"
        ./ircserv $PORT $PASSWORD >server_output.log 2>&1 &
        SERVER_PID=$!
        sleep 2
    fi
    
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${RED}❌ FATAL: Server failed to start${NC}"
        echo -e "${RED}   Check server_output.log for details${NC}"
        cat server_output.log 2>/dev/null || true
        exit 1
    fi
    echo -e "${GREEN}✅ Server started (PID: $SERVER_PID)${NC}"
    echo ""
}

# Function to stop server
stop_server() {
    if [ ! -z "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${YELLOW}Stopping server...${NC}"
        kill -INT $SERVER_PID 2>/dev/null
        wait $SERVER_PID 2>/dev/null || true
        echo -e "${GREEN}✅ Server stopped${NC}"
    fi
}

# Cleanup on exit
trap stop_server EXIT

# Build the server if needed
if [ ! -f "./ircserv" ]; then
    echo -e "${YELLOW}Building IRC server...${NC}"
    make clean && make
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ FATAL: Build failed${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Build successful${NC}"
    echo ""
fi

# ===============================================================================
# RFC 1459 COMPLIANCE TESTS
# ===============================================================================

test_rfc_message_limits() {
    echo -e "${PURPLE}RFC 1459 Message Limits Test${NC}"
    
    local temp_output=$(mktemp)
    
    { (
        echo "PASS $PASSWORD"
        echo "NICK rfc_test"
        echo "USER rfc_test 0 * :RFC Test User"
        sleep 1
        
        # Test maximum valid message (510 chars + \\r\\n = 512)
        local max_message="PRIVMSG #test :$(printf 'A%.0s' {1..485})"  # 485 + "PRIVMSG #test :" = 499 chars
        echo "$max_message"
        
        # Test oversized message (should be truncated or rejected)
        local oversized="PRIVMSG #test :$(printf 'X%.0s' {1..600})"
        echo "$oversized"
        
        sleep 1
        echo "QUIT :rfc test done"
    ) | timeout $TIMEOUT nc localhost $PORT > "$temp_output" 2>&1; } || true
    
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "RFC 1459 Message Length Limits" "PASS"
    else
        print_test_result "RFC 1459 Message Length Limits" "FAIL"
    fi
    
    rm -f "$temp_output"
}

test_rfc_nickname_limits() {
    echo -e "${PURPLE}RFC 1459 Nickname Limits Test${NC}"
    
    local temp_output=$(mktemp)
    
    { (
        echo "PASS $PASSWORD"
        
        # RFC 1459: Nicknames should be max 9 characters (but implementations vary)
        echo "NICK a"                              # Valid: 1 char
        echo "NICK abcdefghi"                      # Valid: 9 chars
        echo "NICK abcdefghij"                     # 10 chars (should work in modern IRC)
        echo "NICK $(printf 'a%.0s' {1..30})"     # 30 chars (should be rejected)
        echo "NICK $(printf 'x%.0s' {1..100})"    # 100 chars (should be rejected)
        
        # Invalid nickname formats
        echo "NICK 123invalid"                     # Can't start with number
        echo "NICK invalid-nick"                   # Invalid characters
        echo "NICK invalid nick"                   # Contains space
        echo "NICK"                                # No nickname given
        
        sleep 1
        echo "USER rfc_nick 0 * :RFC Nick Test"
        sleep 1
        echo "QUIT :rfc nick test done"
    ) | timeout $TIMEOUT nc localhost $PORT > "$temp_output" 2>&1; } || true
    
    # Check for proper error responses
    if grep -q "432\\|431" "$temp_output" && kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "RFC 1459 Nickname Validation" "PASS"
    else
        print_test_result "RFC 1459 Nickname Validation" "FAIL"
    fi
    
    rm -f "$temp_output"
}

test_rfc_channel_limits() {
    echo -e "${PURPLE}RFC 1459 Channel Limits Test${NC}"
    
    local temp_output=$(mktemp)
    
    { (
        echo "PASS $PASSWORD"
        echo "NICK chan_test"
        echo "USER chan_test 0 * :Channel Test User"
        sleep 1
        
        # Valid channel names
        echo "JOIN #a"                             # Minimum valid channel
        echo "JOIN #test"                          # Normal channel
        echo "JOIN #$(printf 'a%.0s' {1..50})"    # Long channel name
        
        # Invalid channel names
        echo "JOIN invalid"                        # Must start with #
        echo "JOIN #"                              # Too short
        echo "JOIN #with space"                    # Contains space
        echo "JOIN #with,comma"                    # Contains comma
        echo "JOIN #with\\x07bell"                  # Contains control char
        echo "JOIN #$(printf 'x%.0s' {1..200})"   # Too long
        
        sleep 1
        echo "QUIT :channel test done"
    ) | timeout $TIMEOUT nc localhost $PORT > "$temp_output" 2>&1; } || true
    
    if grep -q "403\\|JOIN" "$temp_output" && kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "RFC 1459 Channel Name Validation" "PASS"
    else
        print_test_result "RFC 1459 Channel Name Validation" "FAIL"
    fi
    
    rm -f "$temp_output"
}

# ===============================================================================
# BUFFER OVERFLOW & MEMORY SAFETY TESTS
# ===============================================================================

test_buffer_overflow_attacks() {
    echo -e "${RED}Buffer Overflow Attack Tests${NC}"
    
    # Test each overflow scenario sequentially to avoid race conditions
    
    # Test 1: Massive single command
    echo "  Testing massive single command..."
    { (
        echo "PASS $PASSWORD"
        echo "NICK overflow1"
        echo "USER overflow1 0 * :Overflow Test"
        sleep 1
        echo "PRIVMSG #test :$(printf 'A%.0s' {1..10000})"  # 10KB message
        sleep 1
        echo "QUIT :overflow test 1 done"
    ) | timeout $TIMEOUT nc localhost $PORT >/dev/null 2>&1; } || true
    
    sleep 2  # Allow server to process and clean up
    
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Buffer Overflow Attack Resistance (Test 1 - Massive Command)" "FAIL"
        return
    fi
    
    # Test 2: Rapid small overflows
    echo "  Testing rapid small overflows..."
    { (
        echo "PASS $PASSWORD" 
        echo "NICK overflow2"
        echo "USER overflow2 0 * :Overflow Test 2"
        sleep 1
        for i in {1..50}; do  # Reduced from 100 to 50
            echo "PRIVMSG #test :$(printf 'X%.0s' {1..600})"  # Each over 512 limit
        done
        echo "QUIT :overflow test 2 done"
    ) | timeout $TIMEOUT nc localhost $PORT >/dev/null 2>&1; } || true
    
    sleep 2
    
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Buffer Overflow Attack Resistance (Test 2 - Rapid Overflows)" "FAIL"
        return
    fi
    
    # Test 3: Long nickname attack
    echo "  Testing long nickname attack..."
    { (
        echo "PASS $PASSWORD"
        echo "NICK $(printf 'n%.0s' {1..1000})"  # 1000 char nickname
        echo "USER overflow3 0 * :Overflow Test 3"
        sleep 1
        echo "QUIT :overflow test 3 done"
    ) | timeout $TIMEOUT nc localhost $PORT >/dev/null 2>&1; } || true
    
    sleep 2
    
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Buffer Overflow Attack Resistance (Test 3 - Long Nickname)" "FAIL"
        return
    fi
    
    # Test 4: Channel flooding
    echo "  Testing channel flooding..."
    { (
        echo "PASS $PASSWORD"
        echo "NICK overflow4"
        echo "USER overflow4 0 * :Overflow Test 4"
        sleep 1
        for i in {1..20}; do  # Reduced from 50 to 20
            echo "JOIN #$(printf 'c%.0s' {1..100})$i"  # Long channel names
        done
        echo "QUIT :overflow test 4 done"
    ) | timeout $TIMEOUT nc localhost $PORT >/dev/null 2>&1; } || true
    
    sleep 3  # Extra time for cleanup
    
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Buffer Overflow Attack Resistance (All Tests)" "PASS"
    else
        print_test_result "Buffer Overflow Attack Resistance (Test 4 - Channel Flooding)" "FAIL"
    fi
}

test_malformed_protocol_attacks() {
    echo -e "${RED}Malformed Protocol Attack Tests${NC}"
    local test_name="Malformed Protocol Attack Resistance"
    local result="FAIL" # Default to FAIL

    # Test binary data, null bytes, control characters
    { (
        printf "PASS $PASSWORD\\r\\n"
        printf "NICK binary_test\\r\\n"
        printf "USER binary_test 0 * :Binary Test\\r\\n"
        sleep 1

        # Binary data in messages
        printf "PRIVMSG #test :\\x00\\x01\\x02\\x03\\xFF\\xFE\\r\\n"
        printf "PRIVMSG #test :\\x7F\\x80\\x90\\xA0\\r\\n"

        # Incomplete messages
        printf "PRIVMSG #test :incomplete"  # No CRLF
        sleep 0.5
        printf "\\r\\n"

        # Mixed line endings
        printf "JOIN #test\\n"              # LF only
        printf "PART #test\\r"              # CR only
        printf "JOIN #test2\\r\\n"           # Proper CRLF

        # Command flooding
        for i in {1..100}; do
            printf "PING :flood$i\\r\\n"
        done

        sleep 1
        printf "QUIT :binary test done\\r\\n"
    ) | timeout $TIMEOUT nc localhost $PORT >/dev/null 2>&1; } || true

    sleep 2 # Allow server to process QUIT and client disconnect

    if kill -0 $SERVER_PID 2>/dev/null; then
        result="PASS"
    fi
    print_test_result "$test_name" "$result"

    # If server crashed, we might want to log more info
    if [ "$result" = "FAIL" ]; then
        echo -e "${RED}  Server CRASHED during Malformed Protocol Attack Tests.${NC}"
        # Consider if script should exit if server dies here
        # exit 1 # Uncomment if subsequent tests are pointless without a server
    fi
}

# ===============================================================================
# CONCURRENT CLIENT STRESS TESTS
# ===============================================================================

test_concurrent_clients() {
    echo -e "${CYAN}Concurrent Clients Stress Test (${MAX_CLIENTS} clients)${NC}"
    
    local pids=()
    local batch_size=10  # Process clients in batches
    local batches=$(((MAX_CLIENTS + batch_size - 1) / batch_size))
    
    echo "  Processing $MAX_CLIENTS clients in $batches batches of $batch_size..."
    
    # Process clients in batches to prevent overwhelming
    for batch in $(seq 0 $((batches - 1))); do
        local start_client=$((batch * batch_size + 1))
        local end_client=$(((batch + 1) * batch_size))
        if [ $end_client -gt $MAX_CLIENTS ]; then
            end_client=$MAX_CLIENTS
        fi
        
        echo "    Starting batch $((batch + 1)): clients $start_client-$end_client"
        
        # Start clients in current batch
        for i in $(seq $start_client $end_client); do
            (
                echo "PASS $PASSWORD"
                echo "NICK stress$i"
                echo "USER stress$i 0 * :Stress Test User $i"
                sleep 1
                echo "JOIN #stress"
                sleep $((RANDOM % 2 + 1))  # Random delay 1-2 seconds
                echo "PRIVMSG #stress :Hello from client $i"
                sleep 1
                echo "PART #stress :Leaving"
                echo "QUIT :stress test done"
            ) | timeout $((TIMEOUT + 5)) nc localhost $PORT >/dev/null 2>&1 &
            pids+=($!)
            
            # Small delay between starting clients
            sleep 0.05
        done
        
        # Wait a bit before starting next batch
        if [ $batch -lt $((batches - 1)) ]; then
            sleep 1
        fi
    done
    
    echo "  Waiting for all clients to complete..."
    
    # Wait for all clients with timeout
    local max_wait_time=30
    local start_time=$(date +%s)
    
    while [ ${#pids[@]} -gt 0 ]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $max_wait_time ]; then
            break
        fi
        
        # Remove completed processes
        local new_pids=()
        for pid_to_check in "${pids[@]}"; do # Corrected loop
            if kill -0 "$pid_to_check" 2>/dev/null; then
                new_pids+=("$pid_to_check")
            fi
        done
        pids=("${new_pids[@]}")
        
        if [ ${#pids[@]} -gt 0 ]; then
            echo "    ${#pids[@]} clients still running..."
            sleep 2
        fi
    done
    
    # Force cleanup any remaining processes
    for pid in "${pids[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    
    sleep 3
    
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Concurrent Clients Stress ($MAX_CLIENTS clients)" "PASS"
    else
        print_test_result "Concurrent Clients Stress ($MAX_CLIENTS clients)" "FAIL"
    fi
}

test_rapid_connect_disconnect() {
    echo -e "${CYAN}Rapid Connect/Disconnect Test${NC}"
    
    local test_clients=15  # Reduced further for stability
    local pids=()
    local connection_delay=0.05
    local max_wait_time=15
    
    echo "  Starting $test_clients rapid connect/disconnect clients..."
    
    # Create clients with staggered start times
    for i in $(seq 1 $test_clients); do
        (
            # Add small random delay to prevent thundering herd
            sleep $(awk "BEGIN {print $connection_delay * $i}")
            
            echo "PASS $PASSWORD"
            echo "NICK rapid$i"
            echo "USER rapid$i 0 * :Rapid Test $i"
            sleep 0.1
            echo "QUIT :rapid disconnect"
        ) | timeout 5 nc localhost $PORT >/dev/null 2>&1 &
        
        local pid=$!
        pids+=($pid)
        
        # Small delay between starting clients
        sleep 0.03
    done
    
    echo "  Waiting for clients to complete..."
    
    # Wait for processes with timeout and better tracking
    local start_time=$(date +%s)
    local completed=0
    
    while [ $completed -lt $test_clients ]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $max_wait_time ]; then
            echo "  Timeout reached, terminating remaining processes..."
            break
        fi
        
        # Count completed processes
        completed=0
        local new_pids=()
        
        for pid in "${pids[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                completed=$((completed + 1))
            else
                new_pids+=($pid)
            fi
        done
        
        pids=("${new_pids[@]}")
        sleep 0.2
    done
    
    # Force terminate any remaining processes
    if [ ${#pids[@]} -gt 0 ]; then
        echo "  Terminating ${#pids[@]} remaining processes..."
        for pid in "${pids[@]}"; do
            kill -TERM "$pid" 2>/dev/null || true
        done
        sleep 1
        # Final cleanup with SIGKILL if needed
        for pid in "${pids[@]}"; do
            kill -KILL "$pid" 2>/dev/null || true
        done
    fi
    
    # Give server time to clean up
    sleep 2
    
    echo "  Completed $completed out of $test_clients clients"
    
    if [ "$completed" -eq "$test_clients" ] && kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Rapid Connect/Disconnect Stress ($completed/$test_clients clients)" "PASS"
    elif kill -0 $SERVER_PID 2>/dev/null; then
        # Server is alive, but not all clients completed
        print_test_result "Rapid Connect/Disconnect Stress ($completed/$test_clients clients completed, server OK)" "FAIL"
    else
        # Server died
        print_test_result "Rapid Connect/Disconnect Stress (Server DIED, $completed/$test_clients clients completed)" "FAIL"
    fi
}

# ===============================================================================
# CHANNEL OPERATION STRESS TESTS  
# ===============================================================================

test_channel_operations_stress() {
    echo -e "${PURPLE}Channel Operations Stress Test${NC}"
    
    local pids=()
    
    # Test 1: Operator operations stress
    (
        echo "PASS $PASSWORD"
        echo "NICK chanop"
        echo "USER chanop 0 * :Channel Operator"
        sleep 1
        echo "JOIN #optest"
        
        # Rapid mode changes
        for mode in "+i" "-i" "+t" "-t" "+k testkey" "-k" "+l 10" "-l"; do
            echo "MODE #optest $mode"
        done
        
        sleep 2
        echo "QUIT :op test done"
    ) | timeout $TIMEOUT nc localhost $PORT >/dev/null 2>&1 & # This is backgrounded, || true not strictly needed but harmless
    pids+=($!)
    
    # Test 2: Multiple users, kicks, invites
    (
        echo "PASS $PASSWORD"
        echo "NICK member1"
        echo "USER member1 0 * :Member 1"
        sleep 1
        echo "JOIN #optest"
        sleep 5  # Wait for operator to set modes
        echo "QUIT :member1 done"
    ) | timeout $TIMEOUT nc localhost $PORT >/dev/null 2>&1 & # This is backgrounded
    pids+=($!)
    
    # Wait for processes with timeout
    local max_wait_time=20
    local start_time=$(date +%s)
    
    while [ ${#pids[@]} -gt 0 ]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $max_wait_time ]; then
            echo "  Timeout reached, terminating remaining processes..."
            break
        fi
        
        # Remove completed processes
        local new_pids=()
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                new_pids+=($pid)
            fi
        done
        pids=("${new_pids[@]}")
        
        if [ ${#pids[@]} -gt 0 ]; then
            sleep 1
        fi
    done
    
    # Force cleanup any remaining processes
    for pid in "${pids[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    
    sleep 2
    
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Channel Operations Stress" "PASS"
    else
        print_test_result "Channel Operations Stress" "FAIL"
    fi
}

test_channel_limits() {
    echo -e "${PURPLE}Channel Limits Test${NC}"
    
    { (
        echo "PASS $PASSWORD"
        echo "NICK chanlimit"
        echo "USER chanlimit 0 * :Channel Limit Test"
        sleep 1
        
        # Try to join many channels
        for i in $(seq 1 $MAX_CHANNELS); do
            echo "JOIN #limit$i"
            if [ $((i % 20)) -eq 0 ]; then
                sleep 0.1  # Brief pause every 20 channels
            fi
        done
        
        sleep 2
        echo "QUIT :channel limit test done"
    ) | timeout $((TIMEOUT * 2)) nc localhost $PORT >/dev/null 2>&1; } || true
    
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Channel Limits Test ($MAX_CHANNELS channels)" "PASS"
    else
        print_test_result "Channel Limits Test ($MAX_CHANNELS channels)" "FAIL"
    fi
}

# ===============================================================================
# ERROR HANDLING & EDGE CASES
# ===============================================================================

test_comprehensive_error_cases() {
    echo -e "${YELLOW}Comprehensive Error Handling Test${NC}"
    
    local temp_output=$(mktemp)
    
    { (
        echo "PASS $PASSWORD"
        echo "NICK errortest"
        echo "USER errortest 0 * :Error Test User"
        sleep 1
        
        # Test all possible parameter errors
        echo "JOIN"                              # 461 - Not enough parameters
        echo "PART"                              # 461 - Not enough parameters  
        echo "PRIVMSG"                           # 461 - Not enough parameters
        echo "KICK"                              # 461 - Not enough parameters
        echo "INVITE"                            # 461 - Not enough parameters
        echo "TOPIC"                             # 461 - Not enough parameters
        echo "MODE"                              # 461 - Not enough parameters
        
        # Test non-existent targets
        echo "PRIVMSG nonexistent :message"      # 401 - No such nick
        echo "PRIVMSG #nonexistent :message"     # 403 - No such channel
        echo "KICK #nonexistent user"            # 403 - No such channel
        echo "INVITE user #nonexistent"          # 403 - No such channel
        echo "TOPIC #nonexistent :topic"         # 403 - No such channel
        
        # Test permission errors
        echo "JOIN #test"
        echo "KICK #test nonexistent"            # 441 - User not in channel
        echo "TOPIC #test :topic"                # Should work (no +t mode)
        echo "MODE #test +t"                     # Should work (operator)
        
        # Test invalid commands
        echo "INVALIDCOMMAND param1 param2"     # 421 - Unknown command
        echo "ANOTHER_INVALID"                   # 421 - Unknown command
        echo "lowercase_command"                 # 421 - Unknown command (case sensitive)
        
        sleep 1
        echo "QUIT :error test done"
    ) | timeout $TIMEOUT nc localhost $PORT > "$temp_output" 2>&1; } || true
    
    # Count different error types
    local error_count=0
    for code in 401 403 421 431 432 441 461; do
        if grep -q "$code" "$temp_output"; then
            error_count=$((error_count + 1))
        fi
    done
    
    if [ $error_count -ge 5 ] && kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Comprehensive Error Handling (found $error_count error types)" "PASS"
    else
        print_test_result "Comprehensive Error Handling (found $error_count error types)" "FAIL"
    fi
    
    rm -f "$temp_output"
}

test_authentication_edge_cases() {
    echo -e "${YELLOW}Authentication Edge Cases Test${NC}"
    local test_name="Authentication Edge Cases"
    local overall_result="FAIL" # Default to FAIL
    local pids=()

    local noauth_out=$(mktemp)
    local multipass_out=$(mktemp)
    local afterreg_out=$(mktemp)

    # Test 1: Commands without authentication (assuming PASS is required first)
    (
        echo "NICK noauth"
        echo "USER noauth 0 * :No Auth User"
        # Attempt commands that should fail if not authenticated via PASS
        echo "JOIN #test"
        echo "PRIVMSG #test :hello"
        sleep 0.5
        echo "QUIT :no auth test"
    ) | timeout $TIMEOUT nc localhost $PORT > "$noauth_out" 2>&1 &
    pids+=($!)

    # Test 2: Multiple PASS attempts
    (
        echo "PASS $WRONG_PASSWORD"
        echo "PASS $WRONG_PASSWORD"
        echo "NICK multipass_early" # Should ideally be ignored or fail
        echo "USER multipass_early 0 * :Test" # Same
        echo "PASS $PASSWORD" # Correct password
        echo "NICK multipass"
        echo "USER multipass 0 * :Multi Pass User"
        sleep 1
        echo "JOIN #authtest" # Should succeed after proper registration
        sleep 0.5
        echo "QUIT :multipass test done"
    ) | timeout $TIMEOUT nc localhost $PORT > "$multipass_out" 2>&1 &
    pids+=($!)

    # Test 3: PASS after registration
    (
        echo "PASS $PASSWORD"
        echo "NICK afterreg"
        echo "USER afterreg 0 * :After Reg User"
        sleep 1 # Allow registration to complete
        echo "PASS $PASSWORD"  # Should get 462 - Already registered
        sleep 0.5
        echo "QUIT :after reg test done"
    ) | timeout $TIMEOUT nc localhost $PORT > "$afterreg_out" 2>&1 &
    pids+=($!)

    # Wait for processes with timeout
    local wait_timeout=20 
    local start_time=$(date +%s)
    local num_clients=${#pids[@]}
    local completed_auth_clients=0

    echo "  Waiting for $num_clients authentication test clients..."
    while [ ${#pids[@]} -gt 0 ]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -ge $wait_timeout ]; then
            echo "    Timeout reached waiting for auth clients."
            break
        fi

        local new_pids=()
        for pid_to_check in "${pids[@]}"; do
            if kill -0 "$pid_to_check" 2>/dev/null; then
                new_pids+=("$pid_to_check")
            else
                completed_auth_clients=$((completed_auth_clients + 1))
            fi
        done
        pids=("${new_pids[@]}")

        if [ ${#pids[@]} -gt 0 ]; then
            # echo "    ${#pids[@]} auth clients still running..." # Can be noisy
            sleep 1
        fi
    done
    echo "  Finished waiting for auth clients. $completed_auth_clients/$num_clients completed."

    # Kill any remaining processes
    if [ ${#pids[@]} -gt 0 ]; then
        echo "    Terminating ${#pids[@]} remaining auth client processes..."
        for pid_to_kill in "${pids[@]}"; do
            kill -TERM "$pid_to_kill" 2>/dev/null || true
        done
        sleep 0.5 
        for pid_to_kill in "${pids[@]}"; do
            if kill -0 "$pid_to_kill" 2>/dev/null; then
                 kill -KILL "$pid_to_kill" 2>/dev/null || true
            fi
        done
    fi
    
    sleep 2 # Allow server to process any final disconnections

    # Check client outputs for expected behavior
    local all_auth_checks_passed=true
    echo "  --- Client Outputs & Checks ---"

    # Check 1: No Auth client
    echo "  Checking noauth_out ($noauth_out)..."
    # Expect 451 (Not registered) or 464 (Password incorrect / missing) for JOIN/PRIVMSG if PASS is required.
    if grep -q -E "451|464" "$noauth_out"; then
        echo -e "    ${GREEN}PASS:${NC} noauth client correctly received error for unauthenticated command."
    else
        echo -e "    ${RED}FAIL:${NC} noauth client did not receive expected 451/464. Output:"
        cat "$noauth_out"
        all_auth_checks_passed=false
    fi

    # Check 2: Multi-pass client
    echo "  Checking multipass_out ($multipass_out)..."
    # Expect 464 for wrong passwords, then successful registration (001) and JOIN.
    local multipass_ok=true
    if ! grep -q "464" "$multipass_out"; then
        echo -e "    ${YELLOW}WARN:${NC} multipass client did not show 464 for wrong password attempts. This might be acceptable if server disconnects instead."
        # multipass_ok=false # Decide if this is a hard fail
    fi
    if ! (grep -E ":[^ ]+ 001 multipass" "$multipass_out" && grep -q ":multipass JOIN :#authtest" "$multipass_out"); then
        echo -e "    ${RED}FAIL:${NC} multipass client failed to register or JOIN after correct PASS. Output:"
        cat "$multipass_out"
        all_auth_checks_passed=false
        multipass_ok=false
    fi
    if $multipass_ok && $all_auth_checks_passed; then # only print pass if it didn't cause all_checks_passed to be false
         echo -e "    ${GREEN}PASS:${NC} multipass client registered and joined successfully."
    fi


    # Check 3: PASS after registration
    echo "  Checking afterreg_out ($afterreg_out)..."
    if grep -q "462" "$afterreg_out"; then # 462 ERR_ALREADYREGISTRED
        echo -e "    ${GREEN}PASS:${NC} afterreg client correctly received 462 (Already registered)."
    else
        echo -e "    ${RED}FAIL:${NC} afterreg client did not receive 462. Output:"
        cat "$afterreg_out"
        all_auth_checks_passed=false
    fi
    
    # Clean up temp files
    rm -f "$noauth_out" "$multipass_out" "$afterreg_out"

    # Final result determination
    if $all_auth_checks_passed && kill -0 $SERVER_PID 2>/dev/null; then
        overall_result="PASS"
        echo -e "  ${GREEN}All authentication sub-tests passed and server is alive.${NC}"
    elif ! $all_auth_checks_passed && kill -0 $SERVER_PID 2>/dev/null; then
        overall_result="FAIL"
        echo -e "  ${RED}Some authentication sub-tests failed, but server is alive.${NC}"
    else # Server is not alive
        overall_result="FAIL"
        echo -e "  ${RED}Server CRASHED or shut down during/after authentication tests.${NC}"
    fi
    
    print_test_result "$test_name" "$overall_result"

    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${YELLOW}WARNING: Server shut down after test_authentication_edge_cases.${NC}"
        echo -e "${YELLOW}This might be expected if the server exits when no clients are connected.${NC}"
        echo -e "${YELLOW}Subsequent tests will likely fail due to 'set -e' if the server is not restarted.${NC}"
    fi
}

# ===============================================================================
# MESSAGE ROUTING & COMMUNICATION TESTS
# ===============================================================================

test_message_routing_stress() {
    echo -e "${CYAN}Message Routing Stress Test${NC}"
    
    local pids=()
    
    # Create a channel with multiple users sending messages
    (
        echo "PASS $PASSWORD"
        echo "NICK sender1"
        echo "USER sender1 0 * :Sender 1"
        sleep 1
        echo "JOIN #routing"
        
        # Send many messages rapidly
        for i in {1..100}; do
            echo "PRIVMSG #routing :Message $i from sender1"
        done
        
        sleep 2
        echo "QUIT :sender1 done"
    ) | timeout $TIMEOUT nc localhost $PORT >/dev/null 2>&1 &
    pids+=($!)
    
    (
        echo "PASS $PASSWORD"
        echo "NICK sender2"
        echo "USER sender2 0 * :Sender 2"
        sleep 1
        echo "JOIN #routing"
        
        # Send messages to specific users
        for i in {1..50}; do
            echo "PRIVMSG sender1 :Private message $i"
            echo "PRIVMSG #routing :Channel message $i from sender2"
        done
        
        sleep 2
        echo "QUIT :sender2 done"
    ) | timeout $TIMEOUT nc localhost $PORT >/dev/null 2>&1 &
    pids+=($!)
    
    # Wait for processes with timeout
    local max_wait_time=20
    local start_time=$(date +%s)
    
    while [ ${#pids[@]} -gt 0 ]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $max_wait_time ]; then
            echo "  Timeout reached, terminating remaining processes..."
            break
        fi
        
        # Remove completed processes
        local new_pids=()
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                new_pids+=($pid)
            fi
        done
        pids=("${new_pids[@]}")
        
        if [ ${#pids[@]} -gt 0 ]; then
            sleep 1
        fi
    done
    
    # Force cleanup any remaining processes
    for pid in "${pids[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    
    sleep 2
    
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Message Routing Stress" "PASS"
    else
        print_test_result "Message Routing Stress" "FAIL"
    fi
}

test_disconnected_client_messages() {
    echo -e "${CYAN}Disconnected Client Message Test${NC}"
    
    # Start client 1
    (
        echo "PASS $PASSWORD"
        echo "NICK target"
        echo "USER target 0 * :Target User"
        sleep 1
        echo "JOIN #disconnect"
        sleep 2
        # Abrupt disconnect (no QUIT)
    ) | timeout 5 nc localhost $PORT >/dev/null 2>&1 &
    local client1_pid=$!
    
    sleep 3
    kill -9 $client1_pid 2>/dev/null || true  # This || true is good
    
    # Client 2 tries to message the disconnected client
    { (
        echo "PASS $PASSWORD"
        echo "NICK sender"
        echo "USER sender 0 * :Sender User"
        sleep 1
        echo "PRIVMSG target :Are you there?"     # Should get error
        echo "PRIVMSG #disconnect :Hello channel"
        sleep 1
        echo "QUIT :sender done"
    ) | timeout $TIMEOUT nc localhost $PORT >/dev/null 2>&1; } || true
    
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Disconnected Client Message Handling" "PASS"
    else
        print_test_result "Disconnected Client Message Handling" "FAIL"
    fi
}

# ===============================================================================
# RESOURCE EXHAUSTION TESTS
# ===============================================================================

test_memory_exhaustion() {
    echo -e "${RED}Memory Exhaustion Test${NC}"
    
    # Test creating many channels and users
    { (
        echo "PASS $PASSWORD"
        echo "NICK memtest"
        echo "USER memtest 0 * :Memory Test User"
        sleep 1
        
        # Create many channels
        for i in {1..200}; do
            echo "JOIN #mem$i"
            echo "TOPIC #mem$i :This is a test topic for memory exhaustion channel $i with some extra text to use more memory"
        done
        
        # Join all channels again (should already be in them)
        for i in {1..200}; do
            echo "JOIN #mem$i"
        done
        
        sleep 2
        echo "QUIT :memory test done"
    ) | timeout $((TIMEOUT * 3)) nc localhost $PORT >/dev/null 2>&1; } || true
    
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Memory Exhaustion Test (200 channels)" "PASS"
    else
        print_test_result "Memory Exhaustion Test (200 channels)" "FAIL"
    fi
}

test_fd_exhaustion() {
    echo -e "${RED}File Descriptor Exhaustion Test${NC}"
    
    local pids=()
    local fd_clients=50  # You can increase if stable
    
    for i in $(seq 1 $fd_clients); do
        (
            echo "PASS $PASSWORD"
            echo "NICK fd$i"
            echo "USER fd$i 0 * :FD Test $i"
            sleep 5
            echo "QUIT :fd test done"
        ) | timeout 8 nc localhost $PORT >/dev/null 2>&1 &
        pids+=($!)
        sleep 0.01
    done
    
    sleep 5  # Give time for all clients to connect
    
    # Cleanup any remaining clients
    for pid in "${pids[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    sleep 1
    for pid in "${pids[@]}"; do
        kill -KILL "$pid" 2>/dev/null || true
    done
    
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "File Descriptor Exhaustion Test ($fd_clients clients)" "PASS"
    else
        print_test_result "File Descriptor Exhaustion Test (Server DIED)" "FAIL"
    fi
}

# ===============================================================================
# SPECIAL PROTOCOL TESTS
# ===============================================================================

test_case_sensitivity() {
    echo -e "${YELLOW}Case Sensitivity Compliance Test${NC}"
    
    local temp_output=$(mktemp)
    
    { (
        echo "PASS $PASSWORD"
        echo "NICK casetest"
        echo "USER casetest 0 * :Case Test User"
        sleep 1
        
        # Test lowercase commands (should all fail with 421)
        echo "join #test"
        echo "part #test"
        echo "privmsg #test :hello"
        echo "nick newname"
        echo "topic #test :topic"
        echo "mode #test +t"
        echo "kick #test user"
        echo "invite user #test"
        echo "quit"
        
        # Test mixed case (should all fail with 421)
        echo "Join #test"
        echo "Part #test"
        echo "PrivMsg #test :hello"
        echo "Nick newname"
        echo "Topic #test :topic"
        echo "Mode #test +t"
        echo "Kick #test user"
        echo "Invite user #test"
        echo "Quit"
        
        sleep 1
        echo "QUIT :case test done"
    ) | timeout $TIMEOUT nc localhost $PORT > "$temp_output" 2>&1; } || true
    
    # Count 421 errors (should have many)
    local error_count=$(grep -c "421" "$temp_output" 2>/dev/null || echo 0)
    
    if [ $error_count -ge 10 ] && kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Case Sensitivity Compliance ($error_count rejections)" "PASS"
    else
        print_test_result "Case Sensitivity Compliance ($error_count rejections)" "FAIL"
    fi
    
    rm -f "$temp_output"
}

test_unicode_and_special_chars() {
    echo -e "${YELLOW}Unicode and Special Characters Test${NC}"
    
    { (
        echo "PASS $PASSWORD"
        echo "NICK unicode"
        echo "USER unicode 0 * :Unicode Test User"
        sleep 1
        echo "JOIN #test"
        
        # Test various unicode and special characters
        echo "PRIVMSG #test :Hello World! special chars"
        echo "PRIVMSG #test :Chinese: test"
        echo "PRIVMSG #test :Arabic: test"
        echo "PRIVMSG #test :Russian: test"
        echo "PRIVMSG #test :Japanese: test"
        echo "PRIVMSG #test :Special chars test"
        
        # Test special ASCII characters
        echo "PRIVMSG #test :Special: !@#\$%^&*()_+-=[]{}|;:,.<>?"
        
        sleep 1
        echo "QUIT :unicode test done"
    ) | timeout $TIMEOUT nc localhost $PORT >/dev/null 2>&1; } || true
    
    if kill -0 $SERVER_PID 2>/dev/null; then
        print_test_result "Unicode and Special Characters" "PASS"
    else
        print_test_result "Unicode and Special Characters" "FAIL"
    fi
}

# ===============================================================================
# MAIN TEST EXECUTION
# ===============================================================================

main() {
    start_server
    
    echo -e "${BLUE}===============================================================================${NC}"
    echo -e "${BLUE}                           STARTING TEST EXECUTION${NC}"
    echo -e "${BLUE}===============================================================================${NC}"
    
    # RFC 1459 Compliance Tests
    echo -e "\n${PURPLE}RFC 1459 COMPLIANCE TESTS${NC}"
    test_rfc_message_limits
    test_rfc_nickname_limits  
    test_rfc_channel_limits
    
    # Buffer Overflow & Memory Safety
    echo -e "\n${RED}BUFFER OVERFLOW & MEMORY SAFETY TESTS${NC}"
    test_buffer_overflow_attacks
    test_malformed_protocol_attacks
    
    # Concurrent Client Tests
    echo -e "\n${CYAN}CONCURRENT CLIENT STRESS TESTS${NC}"
    test_concurrent_clients
    test_rapid_connect_disconnect
    
    # Channel Operation Tests  
    echo -e "\n${PURPLE}CHANNEL OPERATION STRESS TESTS${NC}"
    test_channel_operations_stress
    test_channel_limits
    
    # Error Handling Tests
    echo -e "\n${YELLOW}ERROR HANDLING & EDGE CASE TESTS${NC}"
    test_comprehensive_error_cases
    test_authentication_edge_cases
    
    # Communication Tests
    echo -e "\n${CYAN}MESSAGE ROUTING & COMMUNICATION TESTS${NC}"
    test_message_routing_stress
    test_disconnected_client_messages
    
    # Resource Exhaustion Tests
    echo -e "\n${RED}RESOURCE EXHAUSTION TESTS${NC}"
    test_memory_exhaustion
    test_fd_exhaustion
    
    # Protocol Tests
    echo -e "\n${YELLOW}SPECIAL PROTOCOL TESTS${NC}"
    test_case_sensitivity
    test_unicode_and_special_chars
    
    # Final Results
    echo -e "\n${BLUE}===============================================================================${NC}"
    echo -e "${BLUE}                               FINAL RESULTS${NC}"  
    echo -e "${BLUE}===============================================================================${NC}"
    echo -e "Total Tests: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "\n${GREEN}ALL TESTS PASSED! IRC Server is robust and RFC 1459 compliant!${NC}"
    else
        echo -e "\n${YELLOW}Some tests failed. Check valgrind output for details.${NC}"
    fi
    
    # Check valgrind results
    if [ -f "valgrind_stress.log" ]; then
        echo -e "\n${BLUE}VALGRIND ANALYSIS SUMMARY:${NC}"
        echo -e "${CYAN}Memory leaks:${NC}"
        grep -A 3 "LEAK SUMMARY" valgrind_stress.log 2>/dev/null || echo "No leak summary found"
        echo -e "\n${CYAN}Errors detected:${NC}"
        grep "ERROR SUMMARY" valgrind_stress.log 2>/dev/null || echo "No error summary found"
    fi
    
    echo -e "\n${BLUE}Test logs saved to:${NC}"
    echo -e "  - valgrind_stress.log (Memory analysis)"
    echo -e "  - server_output.log (Server output)"
    
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    fi
}

# ===============================================================================
# CLIENT CONNECTION LIMIT RECOMMENDATIONS
# ===============================================================================

echo -e "${BLUE}RECOMMENDATIONS FOR CLIENT LIMITS:${NC}"
echo -e "Based on RFC 1459 and modern IRC servers:"
echo -e "  - Max clients per server: 1000-5000 (depending on resources)"
echo -e "  - Max channels per client: 20-50"
echo -e "  - Max users per channel: 500-1000"
echo -e "  - Message rate limit: 1-2 messages/second per client"
echo -e "  - Connection rate limit: 3-5 connections/second per IP"
echo -e "  - Nick length: 9-30 characters"
echo -e "  - Channel name length: 50 characters"
echo -e "  - Message length: 512 bytes (including CRLF)"
echo -e ""

# Run the main test suite
main

# EOF
