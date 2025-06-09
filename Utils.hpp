#ifndef UTILS_HPP
#define UTILS_HPP

#include "ircserv.hpp"

/**
 * @brief Utility functions for the IRC server
 * 
 * This class contains static helper functions that can be used throughout the program.
 * Static functions belong to the class itself, not to any instance of the class.
 * You can call them without creating an object: Utils::functionName()
 */
class Utils {
public:
    // String manipulation
    static std::vector<std::string> split(const std::string& str, char delimiter);
    static std::string trim(const std::string& str);
    static std::string toUpper(const std::string& str);
    static std::string toLower(const std::string& str);
    
    // Network utilities
    static bool sendToClient(Client* client, const std::string& message);
    static std::string getTimestamp();
    
    // Validation functions
    static bool isValidNickname(const std::string& nickname);
    static bool isValidChannelName(const std::string& channelName);
    
    // IRC formatting
    static std::string formatMessage(const std::string& prefix, const std::string& command, 
                                   const std::string& params);
    static std::string formatReply(int code, const std::string& target, const std::string& message);
    
    // Number conversion with error checking
    static bool stringToInt(const std::string& str, int& result);
    static std::string intToString(int value);
};

// IRC numeric reply codes (defined in RFC 1459)
// Using #define for maximum 42 project compatibility
#define RPL_WELCOME 001
#define RPL_YOURHOST 002
#define RPL_CREATED 003
#define RPL_MYINFO 004

#define RPL_TOPIC 332
#define RPL_NAMREPLY 353
#define RPL_ENDOFNAMES 366
#define RPL_CHANNELMODEIS 324

#define ERR_NOSUCHNICK 401
#define ERR_NOSUCHCHANNEL 403
#define ERR_CANNOTSENDTOCHAN 404
#define ERR_NORECIPIENT 411
#define ERR_NOTEXTTOSEND 412
#define ERR_UNKNOWNCOMMAND 421
#define ERR_NONICKNAMEGIVEN 431
#define ERR_ERRONEUSNICKNAME 432
#define ERR_NICKNAMEINUSE 433
#define ERR_USERNOTINCHANNEL 441
#define ERR_NOTONCHANNEL 442
#define ERR_USERONCHANNEL 443
#define ERR_NEEDMOREPARAMS 461
#define ERR_ALREADYREGISTERED 462
#define ERR_PASSWDMISMATCH 464
#define ERR_CHANNELISFULL 471
#define ERR_INVITEONLYCHAN 473
#define ERR_BADCHANNELKEY 475
#define ERR_CHANOPRIVSNEEDED 482

#endif
