#include "Parser.hpp"
#include "Server.hpp"
#include "Client.hpp"
#include "Channel.hpp"
#include "Utils.hpp"

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
        cmd.command = Utils::toUpper(line.substr(pos));
        return cmd;  // No parameters
    }
    
    cmd.command = Utils::toUpper(line.substr(pos, cmdEnd - pos));
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
            cmd.params.push_back(line.substr(pos + 1));
            break;
        }
        
        // Regular parameter
        size_t paramEnd = line.find(' ', pos);
        if (paramEnd == std::string::npos) {
            cmd.params.push_back(line.substr(pos));
            break;
        } else {
            cmd.params.push_back(line.substr(pos, paramEnd - pos));
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
    } else if (cmd.command == "JOIN") {
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
    } else if (cmd.command == "QUIT") {
        handleQuit(client, cmd);
    } else {
        // Unknown command
        sendError(client, IRC::ERR_UNKNOWNCOMMAND, cmd.command + " :Unknown command");
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
    if (client->isRegistered()) {
        sendError(client, IRC::ERR_ALREADYREGISTERED, ":You may not reregister");
        return;
    }
    
    if (cmd.params.empty()) {
        sendError(client, IRC::ERR_NEEDMOREPARAMS, "PASS :Not enough parameters");
        return;
    }
    
    if (cmd.params[0] == _server->getPassword()) {
        client->setAuthenticated(true);
    } else {
        sendError(client, IRC::ERR_PASSWDMISMATCH, ":Password incorrect");
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
    
    if (cmd.params.empty()) {
        sendError(client, IRC::ERR_NEEDMOREPARAMS, "JOIN :Not enough parameters");
        return;
    }
    
    std::string channelName = cmd.params[0];
    std::string key = cmd.params.size() > 1 ? cmd.params[1] : "";
    
    if (!Utils::isValidChannelName(channelName)) {
        sendError(client, IRC::ERR_NOSUCHCHANNEL, channelName + " :No such channel");
        return;
    }
    
    Channel* channel = _server->getChannel(channelName);
    if (!channel) {
        channel = _server->createChannel(channelName);
    }
    
    // Check channel restrictions
    if (channel->isInviteOnly() && !channel->isInvited(client)) {
        sendError(client, IRC::ERR_INVITEONLYCHAN, channelName + " :Cannot join channel (+i)");
        return;
    }
    
    if (channel->hasKey() && channel->getKey() != key) {
        sendError(client, IRC::ERR_BADCHANNELKEY, channelName + " :Cannot join channel (+k)");
        return;
    }
    
    if (channel->hasUserLimit() && channel->getClientCount() >= channel->getUserLimit()) {
        sendError(client, IRC::ERR_CHANNELISFULL, channelName + " :Cannot join channel (+l)");
        return;
    }
    
    // Add client to channel
    channel->addClient(client);
    channel->removeInvited(client);  // Remove from invited list if they were invited
    
    // Send JOIN message to all channel members
    std::string joinMsg = Utils::formatMessage(client->getPrefix(), "JOIN", channelName);
    channel->broadcast(joinMsg);
    
    // Send topic if set
    if (!channel->getTopic().empty()) {
        std::string topicMsg = Utils::formatReply(IRC::RPL_TOPIC, client->getNickname(), 
                                                channelName + " :" + channel->getTopic());
        Utils::sendToClient(client, topicMsg);
    }
    
    // Send names list
    std::string namesMsg = Utils::formatReply(IRC::RPL_NAMREPLY, client->getNickname(),
                                            "= " + channelName + " :" + channel->getUserList());
    Utils::sendToClient(client, namesMsg);
    
    std::string endNamesMsg = Utils::formatReply(IRC::RPL_ENDOFNAMES, client->getNickname(),
                                               channelName + " :End of /NAMES list");
    Utils::sendToClient(client, endNamesMsg);
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
    channel->broadcast(partMsg);
    
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
        channel->broadcast(privmsgMsg, client);  // Exclude sender
    } else {
        // Private message to user
        Client* targetClient = _server->getClientByNick(target);
        if (!targetClient) {
            sendError(client, IRC::ERR_NOSUCHNICK, target + " :No such nick/channel");
            return;
        }
        
        std::string privmsgMsg = Utils::formatMessage(client->getPrefix(), "PRIVMSG", target + " :" + message);
        Utils::sendToClient(targetClient, privmsgMsg);
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
    channel->broadcast(kickMsg);
    
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
    Utils::sendToClient(targetClient, inviteMsg);
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
            std::string topicMsg = Utils::formatReply(IRC::RPL_TOPIC, client->getNickname(),
                                                    channelName + " :" + channel->getTopic());
            Utils::sendToClient(client, topicMsg);
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
        channel->broadcast(topicMsg);
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
            std::string modeMsg = Utils::formatReply(IRC::RPL_CHANNELMODEIS, client->getNickname(),
                                                   target + " " + channel->getModeString());
            Utils::sendToClient(client, modeMsg);
            return;
        }
        
        if (!channel->isOperator(client)) {
            sendError(client, IRC::ERR_CHANOPRIVSNEEDED, target + " :You're not channel operator");
            return;
        }
        
        // Parse mode changes
        std::string modeStr = cmd.params[1];
        bool adding = true;
        size_t paramIndex = 2;
        
        for (size_t i = 0; i < modeStr.length(); ++i) {
            char mode = modeStr[i];
            
            if (mode == '+') {
                adding = true;
            } else if (mode == '-') {
                adding = false;
            } else if (mode == 'i') {
                channel->setInviteOnly(adding);
            } else if (mode == 't') {
                channel->setTopicRestricted(adding);
            } else if (mode == 'k') {
                if (adding && paramIndex < cmd.params.size()) {
                    channel->setKey(cmd.params[paramIndex++]);
                } else if (!adding) {
                    channel->removeKey();
                }
            } else if (mode == 'l') {
                if (adding && paramIndex < cmd.params.size()) {
                    int limit;
                    if (Utils::stringToInt(cmd.params[paramIndex++], limit) && limit > 0) {
                        channel->setUserLimit(static_cast<size_t>(limit));
                    }
                } else if (!adding) {
                    channel->removeUserLimit();
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
                    }
                }
            }
        }
        
        // Broadcast mode change
        std::string modeMsg = Utils::formatMessage(client->getPrefix(), "MODE", target + " " + modeStr);
        channel->broadcast(modeMsg);
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
    std::string welcome = Utils::formatReply(IRC::RPL_WELCOME, nick, 
                                           ":Welcome to the Internet Relay Network " + client->getPrefix());
    Utils::sendToClient(client, welcome);
    
    std::string yourhost = Utils::formatReply(IRC::RPL_YOURHOST, nick,
                                            ":Your host is " + serverName + ", running version 1.0");
    Utils::sendToClient(client, yourhost);
    
    std::string created = Utils::formatReply(IRC::RPL_CREATED, nick,
                                           ":This server was created " + _server->getCreationTime());
    Utils::sendToClient(client, created);
    
    std::string myinfo = Utils::formatReply(IRC::RPL_MYINFO, nick,
                                          serverName + " 1.0 o itklno");
    Utils::sendToClient(client, myinfo);
    
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
    std::string errorMsg = Utils::formatReply(errorCode, nick, message);
    Utils::sendToClient(client, errorMsg);
}
