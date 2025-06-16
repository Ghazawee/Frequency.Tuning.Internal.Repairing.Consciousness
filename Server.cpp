#include "Server.hpp"
#include "Client.hpp"
#include "Channel.hpp"
#include "Parser.hpp"
#include "Utils.hpp"

// Static member definition
Server* Server::_currentServer = NULL;

/**
 * @brief Signal handler for graceful shutdown
 * @param signal The signal number
 * 
 * When the user presses Ctrl+C (SIGINT), this function requests shutdown
 * of the current server instance.
 */
void Server::signalHandler(int signal) {
    (void)signal;  // Suppress unused parameter warning
    if (_currentServer) {
        _currentServer->requestShutdown();
    }
}

/**
 * @brief Request server shutdown
 */
void Server::requestShutdown() {
    _shutdown = true;
    std::cout << "\nServer shutting down gracefully..." << std::endl;
}

/**
 * @brief Constructor for Server class
 * @param port The port to listen on
 * @param password The server password
 */
Server::Server(int port, const std::string& password) 
    : _port(port), _password(password), _serverSocket(-1), _shutdown(false), _parser(NULL) {
    
    _serverName = "ft_irc.42.fr";// maybe set to terminal name
    _creationTime = Utils::getTimestamp();
    
    // Set current server instance for signal handler
    _currentServer = this;
    
    // Set up signal handler for graceful shutdown
    signal(SIGINT, Server::signalHandler);
    signal(SIGTERM, Server::signalHandler);  // Also handle SIGTERM for proper cleanup//maybe not needed
    signal(SIGPIPE, SIG_IGN);  // Ignore SIGPIPE (broken pipe)
    //maybe SIGQUIT as well?
    
    _parser = new Parser(this);
}

/**
 * @brief Destructor for Server class
 */
Server::~Server() {
    shutdown();
    
    if (_parser) {
        delete _parser;
        _parser = NULL;
    }
    
    // Clear static pointer
    if (_currentServer == this) {
        _currentServer = NULL;
    }
}

/**
 * @brief Initialize the server
 * @return true if successful, false otherwise
 */
bool Server::initialize() {
    return setupSocket();
}

/**
 * @brief Main server loop
 * 
 * This is the heart of the server. It uses poll() to wait for activity
 * on any of the connected sockets (server socket or client sockets).
 */
void Server::run() {
    std::cout << "Server started on port " << _port << std::endl;
    
    while (!_shutdown) {
        // Prepare poll array
        _pollFds.clear();
        
        // Add server socket
        struct pollfd serverPoll;
        serverPoll.fd = _serverSocket;
        serverPoll.events = POLLIN;  // We want to know when new connections arrive
        serverPoll.revents = 0;
        _pollFds.push_back(serverPoll);
        
        // Add all client sockets
        for (size_t i = 0; i < _clients.size(); ++i) {
            struct pollfd clientPoll;
            clientPoll.fd = _clients[i]->getFd();
            clientPoll.events = POLLIN;  // We want to know when clients send data
            clientPoll.revents = 0;
            _pollFds.push_back(clientPoll);
        }
        
        // poll() waits for activity on any of the file descriptors
        // timeout of 1000ms (1 second) allows us to check g_shutdown regularly
        int pollResult = poll(&_pollFds[0], _pollFds.size(), 1000);
        
        if (pollResult < 0) {
            if (errno != EINTR) {  // EINTR means interrupted by signal (normal)
                std::cerr << "Poll error: " << strerror(errno) << std::endl;
                break;
            }
            continue;
        }
        
        if (pollResult == 0) {
            continue;  // Timeout, check _shutdown and continue
        }
        
        // Check for new connections on server socket
        if (_pollFds[0].revents & POLLIN) {
            acceptNewClient();
        }
        
        // Check for data from existing clients
        for (size_t i = 1; i < _pollFds.size(); ++i) {
            if (_pollFds[i].revents & POLLIN) {
                Client* client = getClientByFd(_pollFds[i].fd);
                if (client) {
                    processClientData(client);
                }
            }
            
            // Check for client disconnection
            if (_pollFds[i].revents & (POLLHUP | POLLERR)) {
                Client* client = getClientByFd(_pollFds[i].fd);
                if (client) {
                    handleClientDisconnect(client);
                }
            }
        }
    }
}

/**
 * @brief Shutdown the server gracefully
 */
void Server::shutdown() {
    std::cout << "Shutting down server..." << std::endl;
    
    // Close all client connections
    while (!_clients.empty()) {
        removeClient(_clients[0]);
    }
    
    // Clean up all channels
    for (std::map<std::string, Channel*>::iterator it = _channels.begin(); 
         it != _channels.end(); ++it) {
        delete it->second;
    }
    _channels.clear();
    
    // Close server socket
    if (_serverSocket >= 0) {
        close(_serverSocket);
        _serverSocket = -1;
    }
    
    std::cout << "Server shutdown complete." << std::endl;
}

/**
 * @brief Accept a new client connection
 * 
 * accept() creates a new socket for the client connection.
 * We make it non-blocking so it doesn't interfere with poll().
 */
void Server::acceptNewClient() {
    struct sockaddr_in clientAddr;
    socklen_t clientLen = sizeof(clientAddr);
    
    // accept() waits for and accepts a new connection
    int clientFd = accept(_serverSocket, (struct sockaddr*)&clientAddr, &clientLen);
    
    if (clientFd < 0) {
        std::cerr << "Error accepting client: " << strerror(errno) << std::endl;
        return;
    }
    
    // Make client socket non-blocking
    int flags = fcntl(clientFd, F_GETFL, 0);
    if (flags < 0 || fcntl(clientFd, F_SETFL, flags | O_NONBLOCK) < 0) {
        std::cerr << "Error setting client socket to non-blocking: " << strerror(errno) << std::endl;
        close(clientFd);
        return;
    }
    
    // Get client hostname
    std::string hostname = getClientHostname(clientFd);
    
    // Create new client object
    Client* newClient = new Client(clientFd, hostname);
    _clients.push_back(newClient);
    
    std::cout << "New client connected from " << hostname << " (fd: " << clientFd << ")" << std::endl;
}

/**
 * @brief Remove a client safely
 * @param client The client to remove
 */
void Server::removeClient(Client* client) {
    if (!client) return;
    
    std::cout << "Removing client " << client->getNickname() << " (fd: " << client->getFd() << ")" << std::endl;
    
    // Remove client from all channels
    for (std::map<std::string, Channel*>::iterator it = _channels.begin(); 
         it != _channels.end(); ) {
        Channel* channel = it->second;
        if (channel->hasClient(client)) {
            // Send QUIT message to channel members
            if (client->isRegistered()) {
                std::string quitMsg = Utils::formatMessage(client->getPrefix(), "QUIT", ":Client disconnected");
                channel->broadcast(quitMsg, client);
            }
            
            channel->removeClient(client);
            
            // Remove empty channels
            if (channel->getClientCount() == 0) {
                delete channel;
                std::map<std::string, Channel*>::iterator toErase = it;
                ++it;
                _channels.erase(toErase);
                continue;
            }
        }
        ++it;
    }
    
    // Close socket
    close(client->getFd());
    
    // Remove from clients vector
    std::vector<Client*>::iterator it = std::find(_clients.begin(), _clients.end(), client);
    if (it != _clients.end()) {
        _clients.erase(it);
    }
    
    // Delete client object
    delete client;
}

/**
 * @brief Get client by nickname
 * @param nickname The nickname to search for
 * @return Pointer to client or NULL if not found
 */
Client* Server::getClientByNick(const std::string& nickname) {
    for (size_t i = 0; i < _clients.size(); ++i) {
        if (_clients[i]->getNickname() == nickname) {
            return _clients[i];
        }
    }
    return NULL;
}

/**
 * @brief Get client by file descriptor
 * @param fd The file descriptor to search for
 * @return Pointer to client or NULL if not found
 */
Client* Server::getClientByFd(int fd) {
    for (size_t i = 0; i < _clients.size(); ++i) {
        if (_clients[i]->getFd() == fd) {
            return _clients[i];
        }
    }
    return NULL;
}

/**
 * @brief Get channel by name
 * @param name The channel name
 * @return Pointer to channel or NULL if not found
 */
Channel* Server::getChannel(const std::string& name) {
    std::map<std::string, Channel*>::iterator it = _channels.find(name);
    if (it != _channels.end()) {
        return it->second;
    }
    return NULL;
}

/**
 * @brief Create a new channel
 * @param name The channel name
 * @return Pointer to the new channel
 */
Channel* Server::createChannel(const std::string& name) {
    Channel* channel = new Channel(name);
    _channels[name] = channel;
    return channel;
}

/**
 * @brief Remove a channel
 * @param name The channel name
 */
void Server::removeChannel(const std::string& name) {
    std::map<std::string, Channel*>::iterator it = _channels.find(name);
    if (it != _channels.end()) {
        delete it->second;
        _channels.erase(it);
    }
}

/**
 * @brief Process data from a client
 * @param client The client
 * 
 * recv() reads data from the client's socket.
 * We accumulate data in a buffer until we have complete lines.
 */
void Server::processClientData(Client* client) {
    char buffer[512];
    
    // recv() reads data from the socket
    ssize_t bytesRead = recv(client->getFd(), buffer, sizeof(buffer) - 1, 0);
    
    if (bytesRead <= 0) {
        if (bytesRead == 0) {
            std::cout << "Client disconnected gracefully" << std::endl;
        } else {
            std::cerr << "Error reading from client: " << strerror(errno) << std::endl;
        }
        handleClientDisconnect(client);
        return;
    }
    
    buffer[bytesRead] = '\0';
    client->appendToBuffer(buffer);
    
    // Process complete commands (lines ending with \r\n or just \n)
    std::string& clientBuffer = const_cast<std::string&>(client->getBuffer());
    size_t pos = 0;
    
    // First try to find \r\n (proper IRC)
    while ((pos = clientBuffer.find("\r\n")) != std::string::npos) {
        std::string command = clientBuffer.substr(0, pos);
        clientBuffer.erase(0, pos + 2);  // Remove processed command + \r\n
        
        if (!command.empty()) {
            std::cout << command << std::endl;
            IRCCommand cmd = _parser->parseCommand(command);
            _parser->executeCommand(client, cmd);
            
            // Check if client was deleted (e.g., by QUIT command)
            // If client is not in our list anymore, it was deleted
            bool clientExists = false;
            for (size_t i = 0; i < _clients.size(); ++i) {
                if (_clients[i] == client) {
                    clientExists = true;
                    break;
                }
            }
            if (!clientExists) {
                return; // Client was deleted, stop processing
            }
        }
    }
    
    // Also handle lines ending with just \n (for nc compatibility)
    while ((pos = clientBuffer.find("\n")) != std::string::npos) {
        std::string command = clientBuffer.substr(0, pos);
        clientBuffer.erase(0, pos + 1);  // Remove processed command + \n
        
        // Remove trailing \r if present
        if (!command.empty() && command[command.length()-1] == '\r') {
            command.erase(command.length()-1);
        }
        
        if (!command.empty()) {
            std::cout << command << std::endl;
            IRCCommand cmd = _parser->parseCommand(command);
            _parser->executeCommand(client, cmd);
            
            // Check if client was deleted (e.g., by QUIT command)
            bool clientExists = false;
            for (size_t i = 0; i < _clients.size(); ++i) {
                if (_clients[i] == client) {
                    clientExists = true;
                    break;
                }
            }
            if (!clientExists) {
                return; // Client was deleted, stop processing
            }
        }
    }
    
    // Limit buffer size to prevent memory attacks
    if (clientBuffer.length() > 512) {
        clientBuffer.clear();
        handleClientDisconnect(client);
        return; // Important: return immediately after disconnecting // new!!!
    }
}

/**
 * @brief Handle client disconnection
 * @param client The client that disconnected
 */
void Server::handleClientDisconnect(Client* client) {
    removeClient(client);
}

/**
 * @brief Get the server password
 * @return The password
 */
const std::string& Server::getPassword() const {
    return _password;
}

/**
 * @brief Get the server name
 * @return The server name
 */
const std::string& Server::getServerName() const {
    return _serverName;
}

/**
 * @brief Get the server creation time
 * @return The creation time
 */
const std::string& Server::getCreationTime() const {
    return _creationTime;
}

/**
 * @brief Broadcast message to all clients
 * @param message The message to send
 * @param exclude Client to exclude (optional)
 */
void Server::broadcastToAll(const std::string& message, Client* exclude) {
    for (size_t i = 0; i < _clients.size(); ++i) {
        if (_clients[i] != exclude && _clients[i]->isRegistered()) {
            Utils::sendToClient(_clients[i], message);
        }
    }
}

/**
 * @brief Set up the server socket
 * @return true if successful, false otherwise
 * 
 * This function creates and configures the main server socket that listens for connections.
 */
bool Server::setupSocket() {
    // socket() creates a new socket
    // AF_INET = IPv4, SOCK_STREAM = TCP, 0 = default protocol
    _serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (_serverSocket < 0) {
        std::cerr << "Error creating socket: " << strerror(errno) << std::endl;
        return false;
    }
    
    // Set socket options
    int opt = 1;
    // SO_REUSEADDR allows reusing the address immediately after the server stops
    // This prevents "Address already in use" errors when restarting quickly
    if (setsockopt(_serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
        std::cerr << "Error setting SO_REUSEADDR: " << strerror(errno) << std::endl;
        close(_serverSocket);
        return false;
    }
    
    // Make socket non-blocking
    int flags = fcntl(_serverSocket, F_GETFL, 0);
    if (flags < 0 || fcntl(_serverSocket, F_SETFL, flags | O_NONBLOCK) < 0) {
        std::cerr << "Error setting socket to non-blocking: " << strerror(errno) << std::endl;
        close(_serverSocket);
        return false;
    }
    
    // Set up server address
    struct sockaddr_in serverAddr;
    memset(&serverAddr, 0, sizeof(serverAddr));
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_addr.s_addr = INADDR_ANY;  // Accept connections on any interface
    serverAddr.sin_port = htons(_port);       // Convert port to network byte order
    
    // bind() associates the socket with an address
    if (bind(_serverSocket, (struct sockaddr*)&serverAddr, sizeof(serverAddr)) < 0) {
        std::cerr << "Error binding socket: " << strerror(errno) << std::endl;
        close(_serverSocket);
        return false;
    }
    
    // listen() marks the socket as passive (ready to accept connections)
    // 10 is the maximum number of pending connections
    if (listen(_serverSocket, 10) < 0) {
        std::cerr << "Error listening on socket: " << strerror(errno) << std::endl;
        close(_serverSocket);
        return false;
    }
    
    return true;
}

/**
 * @brief Get hostname for a client connection
 * @param clientFd The client's file descriptor
 * @return The hostname or IP address
 */
std::string Server::getClientHostname(int clientFd) {
    struct sockaddr_in clientAddr;
    socklen_t addrLen = sizeof(clientAddr);
    
    // getpeername() gets the address of the peer (client)
    if (getpeername(clientFd, (struct sockaddr*)&clientAddr, &addrLen) < 0) {
        return "unknown";
    }

    // inet_ntoa() converts IP address to string
    return inet_ntoa(clientAddr.sin_addr);
}
