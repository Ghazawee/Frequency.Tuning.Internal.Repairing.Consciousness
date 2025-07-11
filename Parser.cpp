#include "Parser.hpp"
#include "Server.hpp"
#include "Client.hpp"
#include "Channel.hpp"
#include "Utils.hpp"
#include <unistd.h> // For usleep

/**
 * @brief Constructor for Parser class
 * @param server Pointer to the server instance
 */
Parser::Parser(Server* server) : _server(server) {
}

/**
 * @brief Destructor for Parser class
 */
Parser::~Parser() {
    // Nothing to clean up - we don't own the server pointer
}

/**
 * @brief Parse an IRC command from a raw message
 * @param message The raw IRC message
 * @return Parsed IRCCommand structure
 * 
 * IRC messages have the format: [:prefix] COMMAND [param1] [param2] ... [:trailing param]
 * For example: "PRIVMSG #channel :Hello world" or "NICK john"
 */
IRCCommand Parser::parseCommand(const std::string& message) {
    IRCCommand cmd;
    std::string line = Utils::trim(message);
    
    if (line.empty()) {
        return cmd;  // Return empty command
    }
    
    size_t pos = 0;
    
    // Check for prefix (starts with :)
    if (line[0] == ':') {
        size_t spacePos = line.find(' ', 1);
        if (spacePos != std::string::npos) {
            cmd.prefix = line.substr(1, spacePos - 1);
            pos = spacePos + 1;
        }
    }
    
    // Skip whitespace
    while (pos < line.length() && line[pos] == ' ') {
        pos++;
    }
    
    // Extract command
    size_t cmdEnd = line.find(' ', pos);
    if (cmdEnd == std::string::npos) {
        cmd.command = line.substr(pos);  // Keep original case
        return cmd;  // No parameters
    }
    
    cmd.command = line.substr(pos, cmdEnd - pos);  // Keep original case
    pos = cmdEnd + 1;

    // Extract parameters
    while (pos < line.length()) {
        // Skip whitespace
        while (pos < line.length() && line[pos] == ' ') {
            pos++;
        }
        
        if (pos >= line.length()) break;
        
        // Check for trailing parameter (starts with :)
        if (line[pos] == ':') {
            std::string trailingParam = line.substr(pos + 1);
            cmd.params.push_back(trailingParam);
            break;
        }
        
        // Regular parameter
        size_t paramEnd = line.find(' ', pos);
        if (paramEnd == std::string::npos) {
            std::string param = line.substr(pos);
            cmd.params.push_back(param);
            break;
        } else {
            std::string param = line.substr(pos, paramEnd - pos);
            cmd.params.push_back(param);
            pos = paramEnd + 1;
        }
    }
    
    return cmd;
}

/**
 * @brief Execute a parsed IRC command
 * @param client The client who sent the command
 * @param cmd The parsed command
 */
void Parser::executeCommand(Client* client, const IRCCommand& cmd) {
    if (cmd.command.empty()) {
        return;  // Ignore empty commands
    }
    
    // Handle commands based on the command name
    if (cmd.command == "PASS") {
        handlePass(client, cmd);
    } else if (cmd.command == "NICK") {
        handleNick(client, cmd);
    } else if (cmd.command == "USER") {
        handleUser(client, cmd);
    } else if (cmd.command == "QUIT") {
        handleQuit(client, cmd);
    } else if (cmd.command == "CAP") {
        handleCap(client, cmd);
        return;
    } else {
        // For all other commands, require authentication
        if (!client->isAuthenticated()) {
            sendError(client, IRC::ERR_PASSWDMISMATCH, ":Password required");
            return;
        }
        
        if (cmd.command == "JOIN") {
            handleJoin(client, cmd);
        } else if (cmd.command == "PART") {
            handlePart(client, cmd);
        } else if (cmd.command == "PRIVMSG") {
            handlePrivmsg(client, cmd);
        } else if (cmd.command == "KICK") {
            handleKick(client, cmd);
        } else if (cmd.command == "INVITE") {
            handleInvite(client, cmd);
        } else if (cmd.command == "TOPIC") {
            handleTopic(client, cmd);
        } else if (cmd.command == "MODE") {
            handleMode(client, cmd);
        } else if (cmd.command == "PING") {
            handlePing(client, cmd);
        } else if (cmd.command == "WHO") {
            handleWho(client, cmd);
        } else if (cmd.command == "WHOIS") {
            handleWhois(client, cmd);
        } else {
            // Unknown command
            sendError(client, IRC::ERR_UNKNOWNCOMMAND, cmd.command + " :Unknown command");
        }
    }
}

/**
 * @brief Handle PASS command (password authentication)
 * @param client The client
 * @param cmd The command
 * 
 * PASS command sets the connection password. Must be sent before NICK/USER.
 */
void Parser::handlePass(Client* client, const IRCCommand& cmd) {
    // If client is already authenticated, reject
    if (client->isAuthenticated()) {
        sendError(client, IRC::ERR_ALREADYREGISTERED, ":You may not reregister");
        return;
    }
    
    // Check if password is provided
    if (cmd.params.empty()) {
        sendError(client, IRC::ERR_NEEDMOREPARAMS, "PASS :Not enough parameters");
        return;
    }
    
    // Extract password (may have a prefix ":")
    std::string password = cmd.params[0];
    if (!password.empty() && password[0] == ':') {
        password = password.substr(1);
    }
    
    // Validate password
    if (password == _server->getPassword()) {
        client->setAuthenticated(true);
        // No success message is sent for PASS command
    } else {
        sendError(client, IRC::ERR_PASSWDMISMATCH, ":Password incorrect");
        // Note: We do NOT disconnect the client on wrong password.
        // The client remains connected but cannot proceed with registration.
    }
}

/**
 * @brief Handle NICK command (set nickname)
 * @param client The client
 * @param cmd The command
 */
void Parser::handleNick(Client* client, const IRCCommand& cmd) {
    if (cmd.params.empty()) {
        sendError(client, IRC::ERR_NONICKNAMEGIVEN, ":No nickname given");
        return;
    }
    
    std::string newNick = cmd.params[0];
    
    if (!Utils::isValidNickname(newNick)) {
        sendError(client, IRC::ERR_ERRONEUSNICKNAME, newNick + " :Erroneous nickname");
        return;
    }
    
    // Check if nickname is already in use
    Client* existingClient = _server->getClientByNick(newNick);
    if (existingClient && existingClient != client) {
        sendError(client, IRC::ERR_NICKNAMEINUSE, newNick + " :Nickname is already in use");
        return;
    }
    
    std::string oldNick = client->getNickname();
    client->setNickname(newNick);
    
    // If client was already registered, notify other users
    if (client->isRegistered() && !oldNick.empty()) {
        std::string message = Utils::formatMessage(client->getPrefix(), "NICK", newNick);
        _server->broadcastToAll(message, client);
    }
    
    // Check if client is now fully registered
    if (client->isAuthenticated() && !client->getUsername().empty() && !client->isRegistered()) {
        client->setRegistered(true);
        sendWelcome(client);
    } else if (!client->isAuthenticated()) {
        // Send error to let client know authentication is required
        sendError(client, IRC::ERR_PASSWDMISMATCH, ":Password required");
    }
}

/**
 * @brief Handle USER command (set username and real name)
 * @param client The client
 * @param cmd The command
 */
void Parser::handleUser(Client* client, const IRCCommand& cmd) {
    if (client->isRegistered()) {
        sendError(client, IRC::ERR_ALREADYREGISTERED, ":You may not reregister");
        return;
    }
    
    if (cmd.params.size() < 4) {
        sendError(client, IRC::ERR_NEEDMOREPARAMS, "USER :Not enough parameters");
        return;
    }
    
    client->setUsername(cmd.params[0]);
    client->setRealname(cmd.params[3]);
    
    // Check if client is now fully registered
    if (client->isAuthenticated() && !client->getNickname().empty() && !client->isRegistered()) {
        client->setRegistered(true);
        sendWelcome(client);
    } else if (!client->isAuthenticated()) {
        // Send error to let client know authentication is required
        sendError(client, IRC::ERR_PASSWDMISMATCH, ":Password required");
    }
}

/**
 * @brief Handle JOIN command (join a channel)
 * @param client The client
 * @param cmd The command
 */
void Parser::handleJoin(Client* client, const IRCCommand& cmd) {
    if (!client->isRegistered()) {
        return;  // Ignore if not registered
    }
    
    // Check if we have parameters
    if (cmd.params.empty() || cmd.params[0].empty()) {
        sendError(client, IRC::ERR_NEEDMOREPARAMS, "JOIN :Not enough parameters");
        return;
    }
    
    // Split channels and keys from parameters
    std::vector<std::string> channelsToJoin = Utils::split(cmd.params[0], ',');
    std::vector<std::string> keysToUse;
    if (cmd.params.size() > 1) {
        keysToUse = Utils::split(cmd.params[1], ',');
    }
    
    for (size_t i = 0; i < channelsToJoin.size(); i++) {
        std::string channelName = channelsToJoin[i];
        std::string key = i < keysToUse.size() ? keysToUse[i] : "";
        
        // Skip empty channel names (from double commas like "gen,,world")
        if (channelName.empty()) {
            continue;
        }
    
        if (!Utils::isValidChannelName(channelName)) {
            sendError(client, IRC::ERR_NOSUCHCHANNEL, channelName + " :No such channel");
            continue; // Continue with next channel instead of returning
        }
    
    Channel* channel = _server->getChannel(channelName);
    if (!channel) {
        channel = _server->createChannel(channelName);
    }
    
    // Check channel restrictions
    if (channel->isInviteOnly() && !channel->isInvited(client)) {
        sendError(client, IRC::ERR_INVITEONLYCHAN, channelName + " :Cannot join channel (+i)");
        continue;
    }
    
    if (channel->hasKey() && channel->getKey() != key) {
        sendError(client, IRC::ERR_BADCHANNELKEY, channelName + " :Cannot join channel (+k)");
        continue;
    }
    
    if (channel->hasUserLimit() && channel->getClientCount() >= channel->getUserLimit()) {
        sendError(client, IRC::ERR_CHANNELISFULL, channelName + " :Cannot join channel (+l)");
        continue;
    }
    
    // Add client to channel
    channel->addClient(client);
    channel->removeInvited(client);  // Remove from invited list if they were invited
    
    // Send JOIN message to all channel members
    std::string joinMsg = Utils::formatMessage(client->getPrefix(), "JOIN", channelName);
    std::vector<Client*> disconnectedClients = channel->broadcastSafe(joinMsg);
    
    // Handle disconnected clients
    for (size_t i = 0; i < disconnectedClients.size(); ++i) {
        _server->handleClientDisconnect(disconnectedClients[i]);
    }
    
    // Send topic if set
    if (!channel->getTopic().empty()) {
        std::string topicMsg = Utils::formatReply(_server->getServerName(), IRC::RPL_TOPIC, client->getNickname(), 
                                                channelName + " :" + channel->getTopic());
        if (!_server->sendToClientSafe(client, topicMsg)) {
            return; // Client was disconnected
        }
    }
    
    // Send names list
    std::string namesMsg = Utils::formatReply(_server->getServerName(), IRC::RPL_NAMREPLY, client->getNickname(),
                                            "= " + channelName + " :" + channel->getUserList());
    if (!_server->sendToClientSafe(client, namesMsg)) {
        return; // Client was disconnected
    }
    
    std::string endNamesMsg = Utils::formatReply(_server->getServerName(), IRC::RPL_ENDOFNAMES, client->getNickname(),
                                               channelName + " :End of /NAMES list");
    if (!_server->sendToClientSafe(client, endNamesMsg)) {
        return; // Client was disconnected
    }
    }
}

/**
 * @brief Handle PART command (leave a channel)
 * @param client The client
 * @param cmd The command
 */
void Parser::handlePart(Client* client, const IRCCommand& cmd) {
    if (!client->isRegistered()) {
        return;
    }
    
    if (cmd.params.empty()) {
        sendError(client, IRC::ERR_NEEDMOREPARAMS, "PART :Not enough parameters");
        return;
    }
    
    std::string channelName = cmd.params[0];
    std::string reason = cmd.params.size() > 1 ? cmd.params[1] : "";
    
    Channel* channel = _server->getChannel(channelName);
    if (!channel || !channel->hasClient(client)) {
        sendError(client, IRC::ERR_NOTONCHANNEL, channelName + " :You're not on that channel");
        return;
    }
    
    // Send PART message to all channel members
    std::string params = channelName;
    if (!reason.empty()) {
        params += " :" + reason;
    }
    std::string partMsg = Utils::formatMessage(client->getPrefix(), "PART", params);
    std::vector<Client*> disconnectedClients = channel->broadcastSafe(partMsg);
    
    // Handle disconnected clients
    for (size_t i = 0; i < disconnectedClients.size(); ++i) {
        _server->handleClientDisconnect(disconnectedClients[i]);
    }
    
    channel->removeClient(client);
    
    // Remove channel if empty
    if (channel->getClientCount() == 0) {
        _server->removeChannel(channelName);
    }
}

/**
 * @brief Handle PRIVMSG command (send private message)
 * @param client The client
 * @param cmd The command
 */
void Parser::handlePrivmsg(Client* client, const IRCCommand& cmd) {
    if (!client->isRegistered()) {
        return;
    }
    
    if (cmd.params.size() < 2) {
        if (cmd.params.empty()) {
            sendError(client, IRC::ERR_NORECIPIENT, ":No recipient given (PRIVMSG)");
        } else {
            sendError(client, IRC::ERR_NOTEXTTOSEND, ":No text to send");
        }
        return;
    }
    
    std::string target = cmd.params[0];
    std::string message = cmd.params[1];
    
    if (target[0] == '#') {
        // Channel message
        Channel* channel = _server->getChannel(target);
        if (!channel) {
            sendError(client, IRC::ERR_NOSUCHCHANNEL, target + " :No such channel");
            return;
        }
        
        if (!channel->hasClient(client)) {
            sendError(client, IRC::ERR_CANNOTSENDTOCHAN, target + " :Cannot send to channel");
            return;
        }
        
        std::string privmsgMsg = Utils::formatMessage(client->getPrefix(), "PRIVMSG", target + " :" + message);
        std::vector<Client*> disconnectedClients = channel->broadcastSafe(privmsgMsg, client);  // Exclude sender
        
        // Handle disconnected clients
        for (size_t i = 0; i < disconnectedClients.size(); ++i) {
            _server->handleClientDisconnect(disconnectedClients[i]);
        }
    } else {
        // Private message to user
        Client* targetClient = _server->getClientByNick(target);
        if (!targetClient) {
            sendError(client, IRC::ERR_NOSUCHNICK, target + " :No such nick/channel");
            return;
        }
        
        std::string privmsgMsg = Utils::formatMessage(client->getPrefix(), "PRIVMSG", target + " :" + message);
        _server->sendToClientSafe(targetClient, privmsgMsg);
        // Note: If target client disconnects, they'll be cleaned up by poll events
        // We don't return here since the sender's command was successful
    }
}

/**
 * @brief Handle KICK command (kick user from channel)
 * @param client The client (must be operator)
 * @param cmd The command
 */
void Parser::handleKick(Client* client, const IRCCommand& cmd) {
    if (!client->isRegistered()) {
        return;
    }
    
    if (cmd.params.size() < 2) {
        sendError(client, IRC::ERR_NEEDMOREPARAMS, "KICK :Not enough parameters");
        return;
    }
    
    std::string channelName = cmd.params[0];
    std::string targetNick = cmd.params[1];
    std::string reason = cmd.params.size() > 2 ? cmd.params[2] : client->getNickname();
    
    Channel* channel = _server->getChannel(channelName);
    if (!channel) {
        sendError(client, IRC::ERR_NOSUCHCHANNEL, channelName + " :No such channel");
        return;
    }
    
    if (!channel->hasClient(client)) {
        sendError(client, IRC::ERR_NOTONCHANNEL, channelName + " :You're not on that channel");
        return;
    }
    
    if (!channel->isOperator(client)) {
        sendError(client, IRC::ERR_CHANOPRIVSNEEDED, channelName + " :You're not channel operator");
        return;
    }
    
    Client* targetClient = _server->getClientByNick(targetNick);
    if (!targetClient || !channel->hasClient(targetClient)) {
        sendError(client, IRC::ERR_USERNOTINCHANNEL, targetNick + " " + channelName + " :They aren't on that channel");
        return;
    }
    
    // Send KICK message to all channel members
    std::string kickMsg = Utils::formatMessage(client->getPrefix(), "KICK", 
                                             channelName + " " + targetNick + " :" + reason);
    std::vector<Client*> disconnectedClients = channel->broadcastSafe(kickMsg);
    
    // Handle disconnected clients
    for (size_t i = 0; i < disconnectedClients.size(); ++i) {
        _server->handleClientDisconnect(disconnectedClients[i]);
    }
    
    channel->removeClient(targetClient);
}

/**
 * @brief Handle INVITE command (invite user to channel)
 * @param client The client (must be operator)
 * @param cmd The command
 */
void Parser::handleInvite(Client* client, const IRCCommand& cmd) {
    if (!client->isRegistered()) {
        return;
    }
    
    if (cmd.params.size() < 2) {
        sendError(client, IRC::ERR_NEEDMOREPARAMS, "INVITE :Not enough parameters");
        return;
    }
    
    std::string targetNick = cmd.params[0];
    std::string channelName = cmd.params[1];
    
    Channel* channel = _server->getChannel(channelName);
    if (!channel) {
        sendError(client, IRC::ERR_NOSUCHCHANNEL, channelName + " :No such channel");
        return;
    }
    
    if (!channel->hasClient(client)) {
        sendError(client, IRC::ERR_NOTONCHANNEL, channelName + " :You're not on that channel");
        return;
    }
    
    if (!channel->isOperator(client)) {
        sendError(client, IRC::ERR_CHANOPRIVSNEEDED, channelName + " :You're not channel operator");
        return;
    }
    
    Client* targetClient = _server->getClientByNick(targetNick);
    if (!targetClient) {
        sendError(client, IRC::ERR_NOSUCHNICK, targetNick + " :No such nick/channel");
        return;
    }
    
    if (channel->hasClient(targetClient)) {
        sendError(client, IRC::ERR_USERONCHANNEL, targetNick + " " + channelName + " :is already on channel");
        return;
    }
    
    channel->addInvited(targetClient);
    
    // Send INVITE message to target
    std::string inviteMsg = Utils::formatMessage(client->getPrefix(), "INVITE", targetNick + " " + channelName);
    _server->sendToClientSafe(targetClient, inviteMsg);
}

/**
 * @brief Handle TOPIC command (view or change channel topic)
 * @param client The client
 * @param cmd The command
 */
void Parser::handleTopic(Client* client, const IRCCommand& cmd) {
    if (!client->isRegistered()) {
        return;
    }
    
    if (cmd.params.empty()) {
        sendError(client, IRC::ERR_NEEDMOREPARAMS, "TOPIC :Not enough parameters");
        return;
    }
    
    std::string channelName = cmd.params[0];
    
    Channel* channel = _server->getChannel(channelName);
    if (!channel) {
        sendError(client, IRC::ERR_NOSUCHCHANNEL, channelName + " :No such channel");
        return;
    }
    
    if (!channel->hasClient(client)) {
        sendError(client, IRC::ERR_NOTONCHANNEL, channelName + " :You're not on that channel");
        return;
    }
    
    if (cmd.params.size() == 1) {
        // View topic
        if (channel->getTopic().empty()) {
            // No topic set - we could send a "no topic" message, but it's optional
            return;
        } else {
            std::string topicMsg = Utils::formatReply(_server->getServerName(), IRC::RPL_TOPIC, client->getNickname(),
                                                    channelName + " :" + channel->getTopic());
            if (!_server->sendToClientSafe(client, topicMsg)) {
                return; // Client disconnected
            }
        }
    } else {
        // Change topic
        if (channel->isTopicRestricted() && !channel->isOperator(client)) {
            sendError(client, IRC::ERR_CHANOPRIVSNEEDED, channelName + " :You're not channel operator");
            return;
        }
        
        std::string newTopic = cmd.params[1];
        channel->setTopic(newTopic);
        
        // Broadcast topic change
        std::string topicMsg = Utils::formatMessage(client->getPrefix(), "TOPIC", channelName + " :" + newTopic);
        std::vector<Client*> disconnectedClients = channel->broadcastSafe(topicMsg);
        
        // Handle disconnected clients
        for (size_t i = 0; i < disconnectedClients.size(); ++i) {
            _server->handleClientDisconnect(disconnectedClients[i]);
        }
    }
}

/**
 * @brief Handle MODE command (change channel modes)
 * @param client The client
 * @param cmd The command
 */
void Parser::handleMode(Client* client, const IRCCommand& cmd) {
    if (!client->isRegistered()) {
        return;
    }
    
    if (cmd.params.empty()) {
        sendError(client, IRC::ERR_NEEDMOREPARAMS, "MODE :Not enough parameters");
        return;
    }
    
    std::string target = cmd.params[0];
    
    if (target[0] == '#') {
        // Channel mode
        Channel* channel = _server->getChannel(target);
        if (!channel) {
            sendError(client, IRC::ERR_NOSUCHCHANNEL, target + " :No such channel");
            return;
        }
        
        if (!channel->hasClient(client)) {
            sendError(client, IRC::ERR_NOTONCHANNEL, target + " :You're not on that channel");
            return;
        }
        
        if (cmd.params.size() == 1) {
            // View modes
            std::string modeMsg = Utils::formatReply(_server->getServerName(), IRC::RPL_CHANNELMODEIS, client->getNickname(),
                                                   target + " " + channel->getModeString());
            if (!_server->sendToClientSafe(client, modeMsg)) {
                return; // Client disconnected
            }
            return;
        }
        

        
        if (!channel->isOperator(client)) {
            sendError(client, IRC::ERR_CHANOPRIVSNEEDED, target + " :You're not channel operator");
            return;
        }
        
        // Parse mode changes
        std::string modeStr = cmd.params[1];
        
        // Parse mode changes
        bool adding = true;
        size_t paramIndex = 2;
        bool modeChanged = false;
        
        for (size_t i = 0; i < modeStr.length(); ++i) {
            char mode = modeStr[i];
            
            if (mode == '+') {
                adding = true;
            } else if (mode == '-') {
                adding = false;
            } else if (mode == 'i') {
                channel->setInviteOnly(adding);
                modeChanged = true;
            } else if (mode == 't') {
                channel->setTopicRestricted(adding);
                modeChanged = true;
            } else if (mode == 'k') {
                if (adding && paramIndex < cmd.params.size()) {
                    channel->setKey(cmd.params[paramIndex++]);
                    modeChanged = true;
                } else if (!adding) {
                    channel->removeKey();
                    modeChanged = true;
                }
            } else if (mode == 'l') {
                if (adding && paramIndex < cmd.params.size()) {
                    int limit;
                    if (Utils::stringToInt(cmd.params[paramIndex++], limit) && limit > 0) {
                        channel->setUserLimit(static_cast<size_t>(limit));
                        modeChanged = true;
                    }
                } else if (!adding) {
                    channel->removeUserLimit();
                    modeChanged = true;
                }
            } else if (mode == 'o') {
                if (paramIndex < cmd.params.size()) {
                    Client* targetClient = _server->getClientByNick(cmd.params[paramIndex++]);
                    if (targetClient && channel->hasClient(targetClient)) {
                        if (adding) {
                            channel->addOperator(targetClient);
                        } else {
                            channel->removeOperator(targetClient);
                        }
                        modeChanged = true;
                    }
                }
            }
        }
        
        // Only broadcast if we actually changed something
        if (modeChanged) {
            std::string modeMsg = Utils::formatMessage(client->getPrefix(), "MODE", target + " " + modeStr);
            std::vector<Client*> disconnectedClients = channel->broadcastSafe(modeMsg);
            
            // Handle disconnected clients
            for (size_t i = 0; i < disconnectedClients.size(); ++i) {
                _server->handleClientDisconnect(disconnectedClients[i]);
            }
        }
    }
}

/**
 * @brief Handle QUIT command (disconnect from server)
 * @param client The client
 * @param cmd The command
 */
void Parser::handleQuit(Client* client, const IRCCommand& cmd) {
    std::string reason = cmd.params.empty() ? "Client Quit" : cmd.params[0];
    
    // Broadcast quit message to all channels the client is in
    // This will be handled by the server when removing the client
    _server->removeClient(client);
}

/**
 * @brief Send welcome messages to a newly registered client
 * @param client The client to welcome
 */
void Parser::sendWelcome(Client* client) {
    if (client->isWelcomeSent()) {
        return;
    }
    
    std::string nick = client->getNickname();
    std::string serverName = _server->getServerName();
    
    // Send welcome sequence
    std::string welcome = Utils::formatReply(serverName, IRC::RPL_WELCOME, nick, 
                                           ":Welcome to the Internet Relay Network " + client->getPrefix());
    if (!_server->sendToClientSafe(client, welcome)) return;
    
    std::string yourhost = Utils::formatReply(serverName, IRC::RPL_YOURHOST, nick,
                                            ":Your host is " + serverName + ", running version 1.0");
    if (!_server->sendToClientSafe(client, yourhost)) return;
    
    std::string created = Utils::formatReply(serverName, IRC::RPL_CREATED, nick,
                                           ":This server was created " + _server->getCreationTime());
    if (!_server->sendToClientSafe(client, created)) return;
    
    std::string myinfo = Utils::formatReply(serverName, IRC::RPL_MYINFO, nick,
                                          serverName + " 1.0 o itklno");
    if (!_server->sendToClientSafe(client, myinfo)) return;
    
    // Send command help manual (these are informational, if client disconnects it's fine)
    std::string manual1 = ":" + serverName + " NOTICE " + nick + " :Available Commands:";
    if (!_server->sendToClientSafe(client, manual1)) return;
    
    std::string manual2 = ":" + serverName + " NOTICE " + nick + " :JOIN #channel - Join a channel";
    if (!_server->sendToClientSafe(client, manual2)) return;
    
    std::string manual3 = ":" + serverName + " NOTICE " + nick + " :PART #channel - Leave a channel";
    if (!_server->sendToClientSafe(client, manual3)) return;
    
    std::string manual4 = ":" + serverName + " NOTICE " + nick + " :PRIVMSG #channel :message - Send message to channel";
    if (!_server->sendToClientSafe(client, manual4)) return;
    
    std::string manual5 = ":" + serverName + " NOTICE " + nick + " :PRIVMSG nickname :message - Send private message";
    if (!_server->sendToClientSafe(client, manual5)) return;
    
    std::string manual6 = ":" + serverName + " NOTICE " + nick + " :TOPIC #channel :topic - Set channel topic (ops only)";
    if (!_server->sendToClientSafe(client, manual6)) return;
    
    std::string manual7 = ":" + serverName + " NOTICE " + nick + " :KICK #channel nickname - Kick user (ops only)";
    if (!_server->sendToClientSafe(client, manual7)) return;
    
    std::string manual8 = ":" + serverName + " NOTICE " + nick + " :INVITE nickname #channel - Invite user (ops only)";
    if (!_server->sendToClientSafe(client, manual8)) return;
    
    std::string manual9 = ":" + serverName + " NOTICE " + nick + " :MODE #channel +/-itklno - Set channel modes (ops only)";
    if (!_server->sendToClientSafe(client, manual9)) return;
    
    std::string manual10 = ":" + serverName + " NOTICE " + nick + " :QUIT - Disconnect from server";
    if (!_server->sendToClientSafe(client, manual10)) return;
    
    client->setWelcomeSent(true);
}

/**
 * @brief Send an error message to a client
 * @param client The client
 * @param errorCode The numeric error code
 * @param message The error message
 */
void Parser::sendError(Client* client, int errorCode, const std::string& message) {
    std::string nick = client->getNickname().empty() ? "*" : client->getNickname();
    std::string errorMsg = Utils::formatReply(_server->getServerName(), errorCode, nick, message);
    _server->sendToClientSafe(client, errorMsg);
    // Note: If client disconnects on error, that's acceptable behavior
}

/**
 * @brief Handle PING command (keepalive)
 * @param client The client
 * @param cmd The command
 */
void Parser::handlePing(Client* client, const IRCCommand& cmd) {
    std::string target = cmd.params.empty() ? _server->getServerName() : cmd.params[0];
    std::string pongMsg = ":" + _server->getServerName() + " PONG " + _server->getServerName() + " :" + target;
    _server->sendToClientSafe(client, pongMsg);
}

/**
 * @brief Handle WHO command (list users)
 * @param client The client  
 * @param cmd The command
 */
void Parser::handleWho(Client* client, const IRCCommand& cmd) {
    if (!client->isRegistered()) {
        return;
    }
    
    std::string target = cmd.params.empty() ? "*" : cmd.params[0];
    std::string nick = client->getNickname();
    std::string serverName = _server->getServerName();
    
    if (target.empty() || target == "*") {
        // WHO with no target - return all users (simplified)
        std::string whoReply = Utils::formatReply(serverName, IRC::RPL_ENDOFWHO, nick, "* :End of WHO list");
        _server->sendToClientSafe(client, whoReply);
    } else if (target[0] == '#') {
        // WHO for a channel
        Channel* channel = _server->getChannel(target);
        if (channel && channel->hasClient(client)) {
            // Return basic WHO info for channel members
            const std::vector<Client*>& clients = channel->getClients();
            for (size_t i = 0; i < clients.size(); ++i) {
                std::string whoInfo = Utils::formatReply(serverName, IRC::RPL_WHOREPLY, nick,
                    target + " " + clients[i]->getUsername() + " " + clients[i]->getHostname() + 
                    " " + serverName + " " + clients[i]->getNickname() + " H :0 " + clients[i]->getRealname());
                if (!_server->sendToClientSafe(client, whoInfo)) return;
            }
        }
        std::string whoEnd = Utils::formatReply(serverName, IRC::RPL_ENDOFWHO, nick, target + " :End of WHO list");
        _server->sendToClientSafe(client, whoEnd);
    } else {
        // WHO for a specific user
        Client* targetClient = _server->getClientByNick(target);
        if (targetClient) {
            std::string whoInfo = Utils::formatReply(serverName, IRC::RPL_WHOREPLY, nick,
                "* " + targetClient->getUsername() + " " + targetClient->getHostname() + 
                " " + serverName + " " + targetClient->getNickname() + " H :0 " + targetClient->getRealname());
            if (!_server->sendToClientSafe(client, whoInfo)) return;
        }
        std::string whoEnd = Utils::formatReply(serverName, IRC::RPL_ENDOFWHO, nick, target + " :End of WHO list");
        _server->sendToClientSafe(client, whoEnd);
    }
}

/**
 * @brief Handle WHOIS command (get user info)
 * @param client The client
 * @param cmd The command  
 */
void Parser::handleWhois(Client* client, const IRCCommand& cmd) {
    if (!client->isRegistered()) {
        return;
    }
    
    if (cmd.params.empty()) {
        sendError(client, IRC::ERR_NEEDMOREPARAMS, "WHOIS :Not enough parameters");
        return;
    }
    
    std::string targetNick = cmd.params[0];
    std::string nick = client->getNickname();
    std::string serverName = _server->getServerName();
    
    Client* targetClient = _server->getClientByNick(targetNick);
    if (!targetClient) {
        sendError(client, IRC::ERR_NOSUCHNICK, targetNick + " :No such nick/channel");
        return;
    }
    
    // Send WHOIS information
    std::string whoisUser = Utils::formatReply(serverName, IRC::RPL_WHOISUSER, nick,
        targetNick + " " + targetClient->getUsername() + " " + targetClient->getHostname() + " * :" + targetClient->getRealname());
    if (!_server->sendToClientSafe(client, whoisUser)) return;
    
    std::string whoisServer = Utils::formatReply(serverName, IRC::RPL_WHOISSERVER, nick,
        targetNick + " " + serverName + " :ft_irc server");
    if (!_server->sendToClientSafe(client, whoisServer)) return;
    
    std::string whoisEnd = Utils::formatReply(serverName, IRC::RPL_ENDOFWHOIS, nick,
        targetNick + " :End of WHOIS list");
    _server->sendToClientSafe(client, whoisEnd);
}

/**
 * @brief Handle CAP command (client capabilities negotiation)
 * @param client The client
 * @param cmd The command
 * 
 * CAP command is used by modern IRC clients to negotiate capabilities.
 * We provide minimal responses to keep clients happy.
 */
void Parser::handleCap(Client* client, const IRCCommand& cmd) {
    if (cmd.params.empty()) {
        return; // Ignore malformed CAP commands
    }
    
    std::string subcommand = cmd.params[0];
    std::string nick = client->getNickname().empty() ? "*" : client->getNickname();
    
    if (subcommand == "LS") {
        // Client asks: "What capabilities do you support?"
        // We support nothing, so send empty list
        std::string response = ":ft_irc.42.fr CAP " + nick + " LS :";
        _server->sendToClientSafe(client, response);
    } else if (subcommand == "REQ") {
        // Client requests capabilities - we deny all requests
        if (cmd.params.size() > 1) {
            std::string response = ":ft_irc.42.fr CAP " + nick + " NAK :" + cmd.params[1];
            _server->sendToClientSafe(client, response);
        }
    } else if (subcommand == "END") {
        // Client ends CAP negotiation - nothing to do
        return;
    }
}
