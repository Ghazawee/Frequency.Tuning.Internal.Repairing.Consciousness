#ifndef SERVER_HPP
#define SERVER_HPP

#include "ircserv.hpp"

// Forward declarations
class Client;
class Channel;
class Parser;

/**
 * @brief The Server class is the main IRC server
 * 
 * This class manages:
 * - Network connections (listening for new clients)
 * - Client management (adding/removing clients)
 * - Channel management (creating/destroying channels)
 * - Message routing between clients
 */
class Server {
private:
    int _port;                              // Port number to listen on
    std::string _password;                  // Server password
    int _serverSocket;                      // Main server socket file descriptor
    bool _shutdown;                         // Flag to control server shutdown
    
    std::vector<Client*> _clients;          // All connected clients
    std::map<std::string, Channel*> _channels;  // All channels (key = channel name)
    Parser* _parser;                        // Command parser
    
    // Poll-related members for handling multiple connections
    std::vector<struct pollfd> _pollFds;    // Array of file descriptors for poll()
    
    // Server info
    std::string _serverName;                // Server name
    std::string _creationTime;              // When server was created

    // Static pointer to current server instance for signal handler
    static Server* _currentServer;

public:
    // Constructor
    Server(int port, const std::string& password);
    
    // Destructor
    ~Server();
    
    // Main server functions
    bool initialize();                      // Set up the server socket
    void run();                            // Main server loop
    void shutdown();                       // Clean shutdown
    
    // Client management
    void acceptNewClient();                // Accept incoming connections
    void removeClient(Client* client);     // Remove a client safely
    Client* getClientByNick(const std::string& nickname);
    Client* getClientByFd(int fd);
    
    // Channel management
    Channel* getChannel(const std::string& name);
    Channel* createChannel(const std::string& name);
    void removeChannel(const std::string& name);
    
    // Network operations
    void processClientData(Client* client); // Read and process client data
    void handleClientDisconnect(Client* client);
    
    // Getters
    const std::string& getPassword() const;
    const std::string& getServerName() const;
    const std::string& getCreationTime() const;
    
    // Utility functions
    void broadcastToAll(const std::string& message, Client* exclude = NULL);
    
    // Signal handling
    static void signalHandler(int signal);
    void requestShutdown();
    
private:
    // Helper functions
    bool setupSocket();                    // Create and configure server socket
    void cleanupResources();              // Clean up all allocated resources
    std::string getClientHostname(int clientFd);  // Get client's hostname
};

#endif
