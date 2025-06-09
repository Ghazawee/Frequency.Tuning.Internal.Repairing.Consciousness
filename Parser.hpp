#ifndef PARSER_HPP
#define PARSER_HPP

#include "ircserv.hpp"

// Forward declarations
class Server;

/**
 * @brief Structure to represent a parsed IRC command
 * 
 * IRC commands have the format: [prefix] COMMAND [params]
 * For example: "NICK john" has command="NICK" and params=["john"]
 */
struct IRCCommand {
    std::string prefix;                    // Optional prefix (usually empty for client commands)
    std::string command;                   // The IRC command (NICK, USER, JOIN, etc.)
    std::vector<std::string> params;       // Command parameters
};

/**
 * @brief The Parser class handles parsing and executing IRC commands
 * 
 * This class takes raw IRC messages from clients and converts them into
 * IRCCommand structures, then executes the appropriate command.
 */
class Parser {
private:
    Server* _server;    // Pointer to the server instance

public:
    // Constructor
    Parser(Server* server);
    
    // Destructor
    ~Parser();
    
    // Main parsing functions
    IRCCommand parseCommand(const std::string& message);
    void executeCommand(Client* client, const IRCCommand& cmd);
    
    // Command handlers - each IRC command has its own function
    void handlePass(Client* client, const IRCCommand& cmd);
    void handleNick(Client* client, const IRCCommand& cmd);
    void handleUser(Client* client, const IRCCommand& cmd);
    void handleJoin(Client* client, const IRCCommand& cmd);
    void handlePart(Client* client, const IRCCommand& cmd);
    void handlePrivmsg(Client* client, const IRCCommand& cmd);
    void handleKick(Client* client, const IRCCommand& cmd);
    void handleInvite(Client* client, const IRCCommand& cmd);
    void handleTopic(Client* client, const IRCCommand& cmd);
    void handleMode(Client* client, const IRCCommand& cmd);
    void handleQuit(Client* client, const IRCCommand& cmd);
    
    // Helper functions
    void sendWelcome(Client* client);
    void sendError(Client* client, int errorCode, const std::string& message);
};

#endif
