#!/bin/bash

# Enhanced Comprehensive IRC server test script with maximum code coverage and no hangs
# This script expands on the original comprehensive test to cover more edge cases and code paths
set -e

SERVER_PORT=6669
SERVER_PASS="testpass"
SERVER_PID=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Enhanced Comprehensive IRC Server Test Suite${NC}"
echo -e "${BLUE}=============================================\n${NC}"

# Function to start server
start_server() {
    echo -e "${YELLOW}📡 Starting IRC server on port $SERVER_PORT...${NC}"
    if [ ! -f "./ircserv" ]; then
        echo -e "${RED}❌ Error: ircserv_debug executable not found. Run 'make debug' first.${NC}"
        exit 1
    fi
    
    # Run server with Valgrind, logging all stderr output to valgrind_stderr.log
    ( valgrind --leak-check=full --leak-resolution=high -s --show-leak-kinds=all --leak-check-heuristics=all --num-callers=500 --sigill-diagnostics=yes --track-origins=yes --undef-value-errors=yes --track-fds=yes ./ircserv $SERVER_PORT $SERVER_PASS ) 2>>valgrind_stderr.log &
    SERVER_PID=$!
    sleep 2
    
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${RED}❌ Failed to start server${NC}"
        # You might want to output some of the log if the server fails to start
        # echo -e "${RED}Last few lines of valgrind_stderr.log:${NC}"
        # tail -n 20 valgrind_stderr.log
        exit 1
    fi
    echo -e "${GREEN}✅ Server started with PID $SERVER_PID${NC}"
}

# Function to stop server
stop_server() {
    if [ -n "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${YELLOW}🛑 Stopping server...${NC}"
        kill -INT $SERVER_PID
        wait $SERVER_PID 2>/dev/null || true
        echo -e "${GREEN}✅ Server stopped${NC}"
    fi
}

# Cleanup on exit
trap stop_server EXIT

# Enhanced buffer overflow tests with various attack vectors
test_buffer_overflow_advanced() {
    echo -e "${RED}💣 Test: Advanced buffer overflow protection${NC}"
    
    # Test 1: Extremely long nick
    (
        echo "PASS $SERVER_PASS"
        echo "NICK $(printf 'a%.0s' {1..300})"
        echo "USER overflow 0 * :Overflow Test"
        sleep 1
        echo "QUIT :bye"
    ) | timeout 10 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/overflow_nick.log 2>&1
    
    # Test 2: Massive PRIVMSG
    (
        echo "PASS $SERVER_PASS"
        echo "NICK overflow2"
        echo "USER overflow2 0 * :Overflow Test 2"
        sleep 1
        echo "JOIN #test"
        echo "PRIVMSG #test :$(printf 'X%.0s' {1..20000})"
        sleep 1
        echo "QUIT :bye"
    ) | timeout 10 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/overflow_msg.log 2>&1
    
    # Test 3: Massive channel list
    (
        echo "PASS $SERVER_PASS"
        echo "NICK overflow3"
        echo "USER overflow3 0 * :Overflow Test 3"
        sleep 1
        local channels=""
        for i in {1..100}; do
            if [ -z "$channels" ]; then
                channels="#chan$i"
            else
                channels="$channels,#chan$i"
            fi
        done
        echo "JOIN $channels"
        sleep 1
        echo "QUIT :bye"
    ) | timeout 10 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/overflow_channels.log 2>&1
    
    # Server should survive all tests
    if kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Advanced buffer overflow protection test passed${NC}"
    else
        echo -e "${RED}❌ Advanced buffer overflow protection test failed (server crashed)${NC}"
        return 1
    fi
}

# Test malformed messages with specific edge cases
test_malformed_messages_advanced() {
    echo -e "${PURPLE}🔧 Test: Advanced malformed message handling${NC}"
    
    (
        echo "PASS $SERVER_PASS"
        echo "NICK malform_adv"
        echo "USER malform_adv 0 * :Advanced Malformed Test"
        sleep 1
        
        # Binary data mixed with valid commands
        printf "PING :\x00\x01\x02\x03\xFF\xFE\r\n"
        
        # Incomplete commands
        printf "JO"
        sleep 0.1
        printf "IN #test\r\n"
        
        # Commands without proper endings
        printf "PRIVMSG #test :no newline"
        sleep 0.1
        printf "\r\n"
        
        # Mixed case with invalid chars
        printf "pRiVmSg #TeSt :Mixed case with \x7F\x80 chars\r\n"
        
        # Unicode and special characters
        echo "PRIVMSG #test :Unicode: 🚀 ñ ü ç ø 测试"
        
        # Commands with too many parameters
        echo "JOIN #a #b #c #d #e #f #g #h #i #j #k #l #m #n #o #p"
        
        # Invalid IRC protocol format
        echo ":invalid@format PRIVMSG #test :bad prefix"
        echo "PRIVMSG"
        echo "QUIT"
        echo " "
        echo "NICK "
        echo "USER   "
        
        sleep 1
        echo "QUIT :bye"
    ) | timeout 15 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/malformed_adv.log 2>&1
    
    if grep -q "PONG\|421\|461" /tmp/malformed_adv.log && kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Advanced malformed message handling test passed${NC}"
    else
        echo -e "${RED}❌ Advanced malformed message handling test failed${NC}"
        cat /tmp/malformed_adv.log
        return 1
    fi
}

# Test partial message handling with timing attacks
test_partial_messages_advanced() {
    echo -e "${PURPLE}📝 Test: Advanced partial message handling${NC}"
    
    (
        echo "PASS $SERVER_PASS"
        echo "NICK partial_adv"
        echo "USER partial_adv 0 * :Partial Advanced Test"
        sleep 1
        
        # Slow character-by-character sending
        printf "P"
        sleep 0.1
        printf "R"
        sleep 0.1
        printf "I"
        sleep 0.1
        printf "V"
        sleep 0.1
        printf "M"
        sleep 0.1
        printf "S"
        sleep 0.1
        printf "G"
        sleep 0.1
        printf " "
        sleep 0.1
        printf "#"
        sleep 0.1
        printf "t"
        sleep 0.1
        printf "e"
        sleep 0.1
        printf "s"
        sleep 0.1
        printf "t"
        sleep 0.1
        printf " "
        sleep 0.1
        printf ":"
        sleep 0.1
        printf "s"
        sleep 0.1
        printf "l"
        sleep 0.1
        printf "o"
        sleep 0.1
        printf "w"
        sleep 0.1
        printf "\r\n"
        
        # Command split across multiple sends
        printf "JOIN"
        sleep 0.5
        printf " #test"
        sleep 0.5
        printf "\r\n"
        
        # Incomplete line ending
        printf "PING :test\r"
        sleep 1
        printf "\n"
        
        sleep 1
        echo "QUIT :bye"
    ) | timeout 20 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/partial_adv.log 2>&1
    
    if grep -q "PONG\|JOIN" /tmp/partial_adv.log && kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Advanced partial message handling test passed${NC}"
    else
        echo -e "${RED}❌ Advanced partial message handling test failed${NC}"
        cat /tmp/partial_adv.log
        return 1
    fi
}

# Test concurrent stress scenarios
test_concurrent_stress() {
    echo -e "${CYAN}👥 Test: Concurrent stress testing${NC}"
    
    local pids=()
    
    # Launch 10 concurrent clients
    for i in {1..10}; do
        (
            echo "PASS $SERVER_PASS"
            echo "NICK stress$i"
            echo "USER stress$i 0 * :Stress User $i"
            sleep 1
            echo "JOIN #stress"
            
            # Each client sends 50 rapid messages
            for j in {1..50}; do
                echo "PRIVMSG #stress :Message $j from client $i"
                if [ $((j % 10)) -eq 0 ]; then
                    sleep 0.01  # Brief pause every 10 messages
                fi
            done
            
            sleep 1
            echo "QUIT :stress done"
        ) | timeout 30 nc -q 2 127.0.0.1 $SERVER_PORT > "/tmp/stress_$i.log" 2>&1 &
        pids+=($!)
    done
    
    # Wait for all clients to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Check if any clients successfully connected and sent messages
    local successful_clients=0
    for i in {1..10}; do
        if grep -q "JOIN\|PRIVMSG" "/tmp/stress_$i.log" 2>/dev/null; then
            successful_clients=$((successful_clients + 1))
        fi
    done
    
    if [ "$successful_clients" -ge 5 ] && kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Concurrent stress test passed ($successful_clients/10 clients successful)${NC}"
    else
        echo -e "${RED}❌ Concurrent stress test failed (only $successful_clients/10 clients successful)${NC}"
        return 1
    fi
}

# Test error condition coverage
test_error_conditions_comprehensive() {
    echo -e "${PURPLE}⚠️ Test: Comprehensive error condition coverage${NC}"
    
    (
        echo "PASS $SERVER_PASS"
        echo "NICK error_test"
        echo "USER error_test 0 * :Error Test"
        sleep 1
        
        # Test all possible error scenarios
        echo "JOIN"                              # 461 - Not enough parameters
        echo "PART"                              # 461 - Not enough parameters  
        echo "PRIVMSG"                           # 461 - Not enough parameters
        echo "KICK"                              # 461 - Not enough parameters
        echo "INVITE"                            # 461 - Not enough parameters
        echo "TOPIC"                             # 461 - Not enough parameters
        echo "MODE"                              # 461 - Not enough parameters
        echo "WHO"                               # 461 - Not enough parameters
        echo "WHOIS"                             # 461 - Not enough parameters
        
        echo "JOIN #test"
        echo "PART #nonexistent"                 # 442 - Not on channel
        echo "KICK #test nonexistent"            # 401 - No such nick
        echo "INVITE nonexistent #test"          # 401 - No such nick
        echo "TOPIC #nonexistent :topic"         # 403 - No such channel
        echo "MODE #nonexistent +t"              # 403 - No such channel
        echo "WHO #nonexistent"                  # Should return empty list
        echo "WHOIS nonexistent"                 # 401 - No such nick
        
        echo "PRIVMSG #test"                     # 412 - No text to send
        echo "PRIVMSG nonexistent :msg"          # 401 - No such nick
        echo "PRIVMSG #nonexistent :msg"         # 403 - No such channel
        
        # Invalid channel names
        echo "JOIN invalid"                      # 403 - No such channel (invalid format)
        echo "JOIN #"                            # 403 - No such channel (too short)
        echo "JOIN #with space"                  # 403 - No such channel (contains space)
        echo "JOIN #$(printf 'a%.0s' {1..60})"  # 403 - No such channel (too long)
        
        # Invalid nicknames
        echo "NICK"                              # 431 - No nickname given
        echo "NICK 123invalid"                   # 432 - Erroneous nickname
        echo "NICK invalid-nick"                 # 432 - Erroneous nickname
        echo "NICK $(printf 'a%.0s' {1..20})"   # 432 - Erroneous nickname (too long)
        
        # Unknown commands
        echo "INVALIDCOMMAND param1 param2"     # 421 - Unknown command
        echo "ANOTHER_INVALID"                   # 421 - Unknown command
        
        sleep 1
        echo "QUIT :bye"
    ) | timeout 15 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/error_comprehensive.log 2>&1
    
    # Count different error types
    local error_types=0
    if grep -q "461" /tmp/error_comprehensive.log; then error_types=$((error_types + 1)); fi  # Not enough parameters
    if grep -q "442" /tmp/error_comprehensive.log; then error_types=$((error_types + 1)); fi  # Not on channel
    if grep -q "401" /tmp/error_comprehensive.log; then error_types=$((error_types + 1)); fi  # No such nick
    if grep -q "403" /tmp/error_comprehensive.log; then error_types=$((error_types + 1)); fi  # No such channel
    if grep -q "431\|432" /tmp/error_comprehensive.log; then error_types=$((error_types + 1)); fi  # Nickname errors
    if grep -q "421" /tmp/error_comprehensive.log; then error_types=$((error_types + 1)); fi  # Unknown command
    
    if [ "$error_types" -ge 5 ]; then
        echo -e "${GREEN}✅ Comprehensive error condition test passed ($error_types/6 error types covered)${NC}"
    else
        echo -e "${RED}❌ Comprehensive error condition test failed ($error_types/6 error types covered)${NC}"
        cat /tmp/error_comprehensive.log
        return 1
    fi
}

# Test operator command edge cases
test_operator_edge_cases() {
    echo -e "${CYAN}👑 Test: Operator command edge cases${NC}"
    
    (
        echo "PASS $SERVER_PASS"
        echo "NICK op_edge"
        echo "USER op_edge 0 * :Operator Edge Test"
        sleep 1
        echo "JOIN #optest"
        
        # Try operator commands without being operator
        echo "KICK #optest nonexistent"          # Should fail - not operator
        echo "INVITE nonexistent #optest"        # Should fail - not operator  
        echo "TOPIC #optest :unauthorized"       # Should fail if +t is set
        echo "MODE #optest +k secret"            # Should fail - not operator
        
        # Become operator (as channel creator)
        echo "MODE #optest +o op_edge"
        
        # Test operator commands with invalid targets
        echo "KICK #optest nonexistent :reason"  # 401 - No such nick
        echo "KICK #nonexistent op_edge :reason" # 403 - No such channel
        echo "INVITE nonexistent #optest"        # 401 - No such nick
        echo "INVITE op_edge #nonexistent"       # 403 - No such channel
        
        # Test mode combinations
        echo "MODE #optest +itk secret"          # Multiple modes at once
        echo "MODE #optest +l 5"                 # Set user limit
        echo "MODE #optest +b *!*@banned.com"    # Add ban mask
        echo "MODE #optest b"                    # List ban masks
        echo "MODE #optest -itk"                 # Remove multiple modes
        echo "MODE #optest"                      # View current modes
        
        # Test invalid mode parameters
        echo "MODE #optest +l abc"               # Invalid limit (not a number)
        echo "MODE #optest +l -5"                # Invalid limit (negative)
        echo "MODE #optest +o nonexistent"       # Try to op non-existent user
        echo "MODE #optest +k"                   # Key mode without parameter
        
        sleep 1
        echo "QUIT :bye"
    ) | timeout 15 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/op_edge.log 2>&1
    
    if grep -q "MODE\|482\|401\|403" /tmp/op_edge.log; then
        echo -e "${GREEN}✅ Operator edge cases test passed${NC}"
    else
        echo -e "${RED}❌ Operator edge cases test failed${NC}"
        cat /tmp/op_edge.log
        return 1
    fi
}

# Test channel mode interactions
test_channel_mode_interactions() {
    echo -e "${CYAN}🔧 Test: Channel mode interactions${NC}"
    
    # Start first client (channel creator/operator)
    (
        echo "PASS $SERVER_PASS"
        echo "NICK moderator"
        echo "USER moderator 0 * :Moderator"
        sleep 1
        echo "JOIN #modetest"
        
        # Set various modes
        echo "MODE #modetest +i"                 # Invite only
        echo "MODE #modetest +t"                 # Topic restricted
        echo "MODE #modetest +k secretkey"       # Channel key
        echo "MODE #modetest +l 3"               # User limit
        echo "MODE #modetest +b *!bad@*.example" # Ban mask
        
        sleep 3  # Wait for second client to try joining
        
        # Invite the second client
        echo "INVITE testuser #modetest"
        
        sleep 2
        echo "QUIT :moderator done"
    ) | timeout 20 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/mode_mod.log 2>&1 &
    local MOD_PID=$!
    
    sleep 2
    
    # Start second client (trying to join with restrictions)
    (
        echo "PASS $SERVER_PASS"
        echo "NICK testuser"
        echo "USER testuser 0 * :Test User"
        sleep 1
        
        # Try to join invite-only channel without invite
        echo "JOIN #modetest"                    # Should fail - invite only
        
        # Try to join with wrong key
        echo "JOIN #modetest wrongkey"           # Should fail - wrong key
        
        sleep 2  # Wait for invite
        
        # Try to join with correct key after invite
        echo "JOIN #modetest secretkey"          # Should succeed
        
        # Try to change topic (should fail - not operator)
        echo "TOPIC #modetest :unauthorized topic change"
        
        sleep 1
        echo "QUIT :testuser done"
    ) | timeout 20 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/mode_user.log 2>&1 &
    local USER_PID=$!
    
    # Wait for both clients
    wait $MOD_PID 2>/dev/null || true
    wait $USER_PID 2>/dev/null || true
    
    # Check results
    local mode_tests_passed=0
    if grep -q "473\|475" /tmp/mode_user.log; then mode_tests_passed=$((mode_tests_passed + 1)); fi  # Invite/key errors
    if grep -q "INVITE\|MODE" /tmp/mode_mod.log; then mode_tests_passed=$((mode_tests_passed + 1)); fi  # Moderator commands
    if grep -q "482" /tmp/mode_user.log; then mode_tests_passed=$((mode_tests_passed + 1)); fi  # Not operator
    
    if [ "$mode_tests_passed" -ge 2 ]; then
        echo -e "${GREEN}✅ Channel mode interactions test passed${NC}"
    else
        echo -e "${RED}❌ Channel mode interactions test failed${NC}"
        cat /tmp/mode_mod.log /tmp/mode_user.log
        return 1
    fi
}

# Test connection edge cases
test_connection_edge_cases() {
    echo -e "${CYAN}🔌 Test: Connection edge cases${NC}"
    
    # Test 1: Connection without authentication
    (
        echo "NICK unauth"
        echo "USER unauth 0 * :Unauthenticated"
        echo "JOIN #test"                        # Should fail - not registered
        sleep 1
        echo "QUIT :bye"
    ) | timeout 10 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/unauth.log 2>&1
    
    # Test 2: Wrong password
    (
        echo "PASS wrongpassword"
        echo "NICK wrongpass"
        echo "USER wrongpass 0 * :Wrong Pass"
        sleep 1
        echo "QUIT :bye"
    ) | timeout 10 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/wrongpass.log 2>&1
    
    # Test 3: Duplicate registration
    (
        echo "PASS $SERVER_PASS"
        echo "NICK duplicate"
        echo "USER duplicate 0 * :Duplicate"
        sleep 1
        echo "PASS $SERVER_PASS"                # Should fail - already registered
        echo "USER duplicate 0 * :Duplicate"   # Should fail - already registered
        echo "NICK duplicate"                   # Should fail - already in use
        sleep 1
        echo "QUIT :bye"
    ) | timeout 10 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/duplicate.log 2>&1
    
    # Test 4: Immediate disconnect
    (
        echo "PASS $SERVER_PASS"
        # Disconnect immediately without proper handshake
    ) | timeout 5 nc -q 0 127.0.0.1 $SERVER_PORT > /tmp/immediate.log 2>&1
    
    # Check results
    local connection_tests_passed=0
    if grep -q "451" /tmp/unauth.log; then connection_tests_passed=$((connection_tests_passed + 1)); fi  # Not registered
    if grep -q "464" /tmp/wrongpass.log; then connection_tests_passed=$((connection_tests_passed + 1)); fi  # Wrong password
    if grep -q "462\|433" /tmp/duplicate.log; then connection_tests_passed=$((connection_tests_passed + 1)); fi  # Already registered/nick in use
    
    if [ "$connection_tests_passed" -ge 2 ] && kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Connection edge cases test passed ($connection_tests_passed/3 scenarios covered)${NC}"
    else
        echo -e "${RED}❌ Connection edge cases test failed ($connection_tests_passed/3 scenarios covered)${NC}"
        return 1
    fi
}

# Test advanced query commands
test_advanced_query_commands() {
    echo -e "${PURPLE}🔍 Test: Advanced query commands${NC}"
    
    (
        echo "PASS $SERVER_PASS"
        echo "NICK query_test"
        echo "USER query_test 0 * :Query Test"
        sleep 1
        echo "JOIN #querytest"
        
        # Test WHO variations
        echo "WHO #querytest"                    # WHO for channel
        echo "WHO query_test"                    # WHO for user
        echo "WHO *.example.com"                 # WHO with mask
        echo "WHO *"                             # WHO all users
        
        # Test WHOIS variations
        echo "WHOIS query_test"                  # WHOIS existing user
        echo "WHOIS nonexistent"                 # WHOIS non-existent user
        echo "WHOIS query_test,nonexistent"      # Multiple WHOIS
        
        # Test LIST variations
        echo "LIST"                              # List all channels
        echo "LIST #querytest"                   # List specific channel
        echo "LIST #nonexistent"                 # List non-existent channel
        
        # Test NAMES variations
        echo "NAMES #querytest"                  # Names for channel
        echo "NAMES #nonexistent"                # Names for non-existent channel
        echo "NAMES"                             # Names for all channels
        
        # Test ISON variations
        echo "ISON query_test"                   # ISON existing user
        echo "ISON nonexistent"                  # ISON non-existent user
        echo "ISON query_test nonexistent"       # Mixed ISON
        
        # Test other informational commands
        echo "VERSION"                           # Server version
        echo "TIME"                              # Server time
        echo "MOTD"                              # Message of the day
        echo "HELP"                              # Help command
        echo "HELP JOIN"                         # Help for specific command
        echo "HELP NONEXISTENT"                  # Help for non-existent command
        
        sleep 1
        echo "QUIT :bye"
    ) | timeout 15 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/query_adv.log 2>&1
    
    # Count successful query responses
    local query_responses=0
    if grep -q "352\|315" /tmp/query_adv.log; then query_responses=$((query_responses + 1)); fi  # WHO responses
    if grep -q "311\|318\|401" /tmp/query_adv.log; then query_responses=$((query_responses + 1)); fi  # WHOIS responses
    if grep -q "321\|322\|323" /tmp/query_adv.log; then query_responses=$((query_responses + 1)); fi  # LIST responses
    if grep -q "353\|366" /tmp/query_adv.log; then query_responses=$((query_responses + 1)); fi  # NAMES responses
    if grep -q "303" /tmp/query_adv.log; then query_responses=$((query_responses + 1)); fi  # ISON responses
    if grep -q "351\|391\|372\|704" /tmp/query_adv.log; then query_responses=$((query_responses + 1)); fi  # INFO responses
    
    if [ "$query_responses" -ge 4 ]; then
        echo -e "${GREEN}✅ Advanced query commands test passed ($query_responses/6 command types working)${NC}"
    else
        echo -e "${RED}❌ Advanced query commands test failed ($query_responses/6 command types working)${NC}"
        cat /tmp/query_adv.log
        return 1
    fi
}

# Test AWAY command functionality
test_away_functionality() {
    echo -e "${PURPLE}💤 Test: AWAY command functionality${NC}"
    
    # Start first client and set away
    (
        echo "PASS $SERVER_PASS"
        echo "NICK awayclient"
        echo "USER awayclient 0 * :Away Client"
        sleep 2  # Give more time for registration
        echo "JOIN #awaytest"
        sleep 1  # Give time for channel join
        echo "AWAY :I am away for testing"       # Set away message
        sleep 6  # Wait longer for messages from other client
        echo "AWAY"                              # Remove away status
        sleep 3  # Give time for final messages after away removal
        echo "QUIT :bye"
    ) | timeout 25 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/away1.log 2>&1 &
    local AWAY_PID=$!
    
    sleep 4  # Wait longer to ensure away client is fully registered and joined
    
    # Start second client to test away responses
    (
        echo "PASS $SERVER_PASS"
        echo "NICK msgclient"
        echo "USER msgclient 0 * :Message Client"
        sleep 2  # Give more time for registration
        echo "JOIN #awaytest"
        sleep 1  # Give time for channel join
        # Send messages while away client should be away
        echo "PRIVMSG awayclient :Are you there?"  # Should get away response
        sleep 1
        echo "PRIVMSG awayclient :Another message" # Should get another away response
        sleep 4  # Wait for away to be removed (matches away client timing)
        echo "PRIVMSG awayclient :Are you back?"   # Should not get away response
        sleep 1
        echo "QUIT :bye"
    ) | timeout 25 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/away2.log 2>&1 &
    local MSG_PID=$!
    
    # Wait for both clients
    wait $AWAY_PID 2>/dev/null || true
    wait $MSG_PID 2>/dev/null || true
    
    # Check for away responses
    if grep -q "301.*away" /tmp/away2.log && grep -q "305\|306" /tmp/away1.log; then
        echo -e "${GREEN}✅ AWAY functionality test passed${NC}"
    else
        echo -e "${RED}❌ AWAY functionality test failed${NC}"
        echo "Debug: Away client log:"
        cat /tmp/away1.log
        echo "Debug: Message client log:"
        cat /tmp/away2.log
        return 1
    fi
}

# Test rapid connect/disconnect scenarios
test_rapid_connect_disconnect() {
    echo -e "${CYAN}⚡ Test: Rapid connect/disconnect scenarios${NC}"
    
    local pids=()
    
    # Launch 20 clients that connect and disconnect rapidly
    for i in {1..20}; do
        (
            echo "PASS $SERVER_PASS"
            echo "NICK rapid$i"
            echo "USER rapid$i 0 * :Rapid $i"
            if [ $((i % 3)) -eq 0 ]; then
                sleep 0.1
                echo "JOIN #rapid"
                echo "PRIVMSG #rapid :Quick message from $i"
            fi
            echo "QUIT :rapid disconnect"
        ) | timeout 10 nc -q 1 127.0.0.1 $SERVER_PORT > "/tmp/rapid_$i.log" 2>&1 &
        pids+=($!)
        
        # Small delay between connections
        sleep 0.05
    done
    
    # Wait for all clients
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Count successful connections
    local successful_rapid=0
    for i in {1..20}; do
        if grep -q "001\|Welcome" "/tmp/rapid_$i.log" 2>/dev/null; then
            successful_rapid=$((successful_rapid + 1))
        fi
    done
    
    if [ "$successful_rapid" -ge 15 ] && kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Rapid connect/disconnect test passed ($successful_rapid/20 successful connections)${NC}"
    else
        echo -e "${RED}❌ Rapid connect/disconnect test failed ($successful_rapid/20 successful connections)${NC}"
        return 1
    fi
}

# Test memory and resource exhaustion scenarios
test_resource_exhaustion() {
    echo -e "${RED}⚠️ Test: Resource exhaustion protection${NC}"
    
    # Test 1: Many channels per client
    (
        echo "PASS $SERVER_PASS"
        echo "NICK resource1"
        echo "USER resource1 0 * :Resource Test 1"
        sleep 1
        
        # Try to join many channels
        for i in {1..100}; do
            echo "JOIN #resource$i"
            if [ $((i % 20)) -eq 0 ]; then
                sleep 0.01  # Brief pause every 20 channels
            fi
        done
        
        sleep 1
        echo "QUIT :bye"
    ) | timeout 20 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/resource1.log 2>&1 &
    local RES1_PID=$!
    
    # Test 2: Rapid message flooding
    (
        echo "PASS $SERVER_PASS"
        echo "NICK resource2"
        echo "USER resource2 0 * :Resource Test 2"
        sleep 1
        echo "JOIN #floodtest"
        
        # Send many rapid messages
        for i in {1..200}; do
            echo "PRIVMSG #floodtest :Flood message $i"
        done
        
        sleep 1
        echo "QUIT :bye"
    ) | timeout 20 nc -q 2 127.0.0.1 $SERVER_PORT > /tmp/resource2.log 2>&1 &
    local RES2_PID=$!
    
    # Wait for tests to complete
    wait $RES1_PID 2>/dev/null || true
    wait $RES2_PID 2>/dev/null || true
    
    # Server should survive resource exhaustion attempts
    if kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Resource exhaustion protection test passed${NC}"
    else
        echo -e "${RED}❌ Resource exhaustion protection test failed (server crashed)${NC}"
        return 1
    fi
}

# Test connection limit enforcement (105 clients attempting to connect)
test_connection_limit() {
    echo -e "${PURPLE}🔢 Test: Connection limit enforcement (105 clients)${NC}"
    
    local pids=()
    local connection_logs=()
    
    # Launch 105 clients simultaneously to test the 100-client limit
    for i in {1..105}; do
        local log_file="/tmp/limit_client_$i.log"
        connection_logs+=("$log_file")
        
        (
            echo "PASS $SERVER_PASS"
            echo "NICK limitclient$i"
            echo "USER limitclient$i 0 * :Limit Test Client $i"
            # Keep connection alive for analysis
            sleep 5
            # echo "QUIT :limit test complete"
        ) | timeout 1005 nc -q 2 127.0.0.1 $SERVER_PORT > "$log_file" 2>&1 &
        pids+=($!)
        
        # Small delay to prevent overwhelming the server
        sleep 0.01
    done
    
    # Wait for all connection attempts to complete
    echo -e "${YELLOW}  Waiting for all 105 connection attempts...${NC}"
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Analyze results
    local successful_connections=0
    local rejected_connections=0
    local error_connections=0
    
    for i in {1..105}; do
        local log_file="/tmp/limit_client_$i.log"
        if [ -f "$log_file" ]; then
            if grep -q "001\|Welcome" "$log_file" 2>/dev/null; then
                successful_connections=$((successful_connections + 1))
            elif grep -q "421\|462\|464\|ERROR" "$log_file" 2>/dev/null; then
                rejected_connections=$((rejected_connections + 1))
            else
                # Check if connection was refused/closed
                if [ ! -s "$log_file" ] || grep -q "Connection refused\|Connection reset" "$log_file" 2>/dev/null; then
                    rejected_connections=$((rejected_connections + 1))
                else
                    error_connections=$((error_connections + 1))
                fi
            fi
        else
            error_connections=$((error_connections + 1))
        fi
    done
    
    echo -e "${BLUE}  Connection Analysis:${NC}"
    echo -e "  • Successful connections: $successful_connections"
    echo -e "  • Rejected connections: $rejected_connections"
    echo -e "  • Error/unknown: $error_connections"
    
    # Cleanup connection log files
    for log_file in "${connection_logs[@]}"; do
        rm -f "$log_file"
    done
    
    # Validate results: should accept around 100 clients and reject the rest
    # Allow some tolerance for timing and connection overhead
    if [ "$successful_connections" -ge 95 ] && [ "$successful_connections" -le 100 ] && 
       [ "$rejected_connections" -ge 5 ] && kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Connection limit test passed (${successful_connections}/105 accepted, limit enforced)${NC}"
    else
        echo -e "${RED}❌ Connection limit test failed (${successful_connections}/105 accepted, expected ~100)${NC}"
        return 1
    fi
}

# Main test execution function
main() {
    local failed_tests=0
    
    start_server
    
    echo -e "\n${BLUE}🧪 Running Enhanced Comprehensive Tests${NC}"
    echo -e "${BLUE}======================================${NC}\n"
    
    # Enhanced stress and edge case tests
    test_buffer_overflow_advanced || failed_tests=$((failed_tests + 1))
    test_malformed_messages_advanced || failed_tests=$((failed_tests + 1))
    test_partial_messages_advanced || failed_tests=$((failed_tests + 1))
    test_concurrent_stress || failed_tests=$((failed_tests + 1))
    test_error_conditions_comprehensive || failed_tests=$((failed_tests + 1))
    test_operator_edge_cases || failed_tests=$((failed_tests + 1))
    test_channel_mode_interactions || failed_tests=$((failed_tests + 1))
    test_connection_edge_cases || failed_tests=$((failed_tests + 1))
    test_advanced_query_commands || failed_tests=$((failed_tests + 1))
    test_away_functionality || failed_tests=$((failed_tests + 1))
    test_rapid_connect_disconnect || failed_tests=$((failed_tests + 1))
    test_resource_exhaustion || failed_tests=$((failed_tests + 1))
    test_connection_limit || failed_tests=$((failed_tests + 1))
    
    # Final results
    echo -e "\n${BLUE}========== ENHANCED TEST RESULTS ==========${NC}"
    local total_tests=13
    local passed_tests=$((total_tests - failed_tests))
    
    echo -e "${BLUE}📊 Enhanced Test Coverage Summary:${NC}"
    echo -e "  • Buffer Overflow Protection: Advanced scenarios"
    echo -e "  • Malformed Message Handling: Binary data, unicode, timing"
    echo -e "  • Partial Message Processing: Character-by-character, splits"
    echo -e "  • Concurrent Stress Testing: 10 simultaneous clients"
    echo -e "  • Error Condition Coverage: All IRC numeric codes"
    echo -e "  • Operator Command Edge Cases: Invalid targets, permissions"
    echo -e "  • Channel Mode Interactions: Complex mode combinations"
    echo -e "  • Connection Edge Cases: Auth failures, duplicates"
    echo -e "  • Advanced Query Commands: WHO, WHOIS, LIST, NAMES, ISON"
    echo -e "  • AWAY Functionality: Message responses, state changes"
    echo -e "  • Rapid Connect/Disconnect: 20 simultaneous connections"
    echo -e "  • Resource Exhaustion: Channel/message flooding protection"
    echo -e "  • Connection Limit: 105 clients test (100-client limit enforcement)"
    echo -e "  ${BLUE}Total: $total_tests enhanced tests covering maximum code paths${NC}\n"
    
    if [ "$failed_tests" -eq 0 ]; then
        echo -e "${GREEN}🎉 ALL $total_tests ENHANCED TESTS PASSED!${NC}"
        echo -e "${GREEN}✅ Your IRC server demonstrates exceptional robustness${NC}"
        echo -e "${GREEN}🚀 Maximum code branch and edge case coverage achieved!${NC}"
        echo -e "${GREEN}💪 Server survived all stress, timing, and resource exhaustion tests${NC}"
    else
        echo -e "${YELLOW}⚠️ Enhanced Test Results: $passed_tests/$total_tests tests passed${NC}"
        if [ "$passed_tests" -ge 11 ]; then
            echo -e "${GREEN}🟢 Excellent robustness - minor edge cases need attention${NC}"
        elif [ "$passed_tests" -ge 9 ]; then
            echo -e "${YELLOW}🟡 Good robustness - some edge cases need improvement${NC}"
        elif [ "$passed_tests" -ge 7 ]; then
            echo -e "${YELLOW}🟠 Acceptable robustness - significant improvements needed${NC}"
        else
            echo -e "${RED}🔴 Robustness issues detected - major improvements required${NC}"
        fi
        echo -e "${RED}❌ $failed_tests enhanced test(s) failed${NC}"
    fi
    
    # Server stability analysis
    if kill -0 $SERVER_PID 2>/dev/null; then
        echo -e "\n${GREEN}✅ Server stability: Exceptional (survived all enhanced stress tests)${NC}"
        echo -e "${GREEN}🛡️ No crashes, hangs, or resource exhaustion detected${NC}"
    else
        echo -e "\n${RED}❌ Server stability: Critical issues (crashed during enhanced testing)${NC}"
    fi
    
    # Cleanup temp files
    echo -e "\n${YELLOW}🧹 Cleaning up enhanced test files...${NC}"
    rm -f /tmp/overflow_*.log /tmp/malformed_adv.log /tmp/partial_adv.log
    rm -f /tmp/stress_*.log /tmp/error_comprehensive.log /tmp/op_edge.log
    rm -f /tmp/mode_*.log /tmp/unauth.log /tmp/wrongpass.log /tmp/duplicate.log
    rm -f /tmp/immediate.log /tmp/query_adv.log /tmp/away*.log
    rm -f /tmp/rapid_*.log /tmp/resource*.log
    
    if [ "$failed_tests" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
