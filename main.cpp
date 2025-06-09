#include "ircserv.hpp"
#include "Server.hpp"
#include "Utils.hpp"

/**
 * @brief Print usage information
 * @param programName The name of the program
 */
void printUsage(const std::string& programName) {
    std::cerr << "Usage: " << programName << " <port> <password>" << std::endl;
    std::cerr << "  port:     The port number to listen on (1024-65535)" << std::endl;
    std::cerr << "  password: The connection password for clients" << std::endl;
}

/**
 * @brief Validate port number
 * @param portStr String representation of port
 * @param port Reference to store validated port
 * @return true if valid, false otherwise
 */
bool validatePort(const std::string& portStr, int& port) {
    if (!Utils::stringToInt(portStr, port)) {
        std::cerr << "Error: Invalid port number format" << std::endl;
        return false;
    }
    
    if (port < 1024 || port > 65535) {
        std::cerr << "Error: Port must be between 1024 and 65535" << std::endl;
        return false;
    }
    
    return true;
}

/**
 * @brief Validate password
 * @param password The password to validate
 * @return true if valid, false otherwise
 */
bool validatePassword(const std::string& password) {
    if (password.empty()) {
        std::cerr << "Error: Password cannot be empty" << std::endl;
        return false;
    }
    
    if (password.length() > 50) {
        std::cerr << "Error: Password too long (max 50 characters)" << std::endl;
        return false;
    }
    
    // Check for invalid characters
    for (size_t i = 0; i < password.length(); ++i) {
        char c = password[i];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            std::cerr << "Error: Password cannot contain whitespace" << std::endl;
            return false;
        }
    }
    
    return true;
}

/**
 * @brief Main function - entry point of the program
 * @param argc Number of command-line arguments
 * @param argv Array of command-line arguments
 * @return 0 on success, 1 on error
 * 
 * argc (argument count) tells us how many arguments were passed.
 * argv (argument vector) is an array of strings containing the arguments.
 * argv[0] is always the program name.
 */
int main(int argc, char* argv[]) {
    // Check if correct number of arguments provided
    if (argc != 3) {
        printUsage(argv[0]);
        return 1;
    }
    
    // Parse and validate port
    int port;
    if (!validatePort(argv[1], port)) {
        return 1;
    }
    
    // Validate password
    std::string password = argv[2];
    if (!validatePassword(password)) {
        return 1;
    }
    
    // Print startup information
    std::cout << "Starting IRC Server..." << std::endl;
    std::cout << "Port: " << port << std::endl;
    std::cout << "Password: [HIDDEN]" << std::endl;
    std::cout << "Press Ctrl+C to stop the server" << std::endl;
    std::cout << "----------------------------------------" << std::endl;
    
    // Create server instance
    Server* server = NULL;
    
    try {
        server = new Server(port, password);
        
        // Initialize server (set up socket)
        if (!server->initialize()) {
            std::cerr << "Error: Failed to initialize server" << std::endl;
            delete server;
            return 1;
        }
        
        // Run the main server loop
        server->run();
        
        // Clean up
        delete server;
        
    } catch (const std::exception& e) {
        std::cerr << "Exception caught: " << e.what() << std::endl;
        if (server) {
            delete server;
        }
        return 1;
    } catch (...) {
        std::cerr << "Unknown exception caught" << std::endl;
        if (server) {
            delete server;
        }
        return 1;
    }
    
    std::cout << "Server stopped." << std::endl;
    return 0;
}

/**
 * EXPLANATION OF KEY CONCEPTS USED:
 * 
 * 1. POINTERS:
 *    - int* ptr: A pointer to an integer
 *    - new/delete: Allocate/deallocate memory on the heap
 *    - NULL: Special pointer value meaning "points to nothing"
 * 
 * 2. REFERENCES:
 *    - int& ref: A reference is like an alias to a variable
 *    - Must be initialized when declared
 *    - Cannot be reassigned to refer to something else
 * 
 * 3. VECTORS:
 *    - std::vector<Type>: Dynamic array that can grow/shrink
 *    - push_back(): Add element to end
 *    - size(): Get number of elements
 *    - operator[]: Access element by index
 * 
 * 4. MAPS:
 *    - std::map<Key, Value>: Associative container (key-value pairs)
 *    - Automatically sorted by key
 *    - Use [] operator to access/insert
 * 
 * 5. CONST:
 *    - const int x: Variable cannot be modified
 *    - const int& getX() const: Function doesn't modify object
 *    - Helps prevent bugs and shows intent
 * 
 * 6. NETWORKING FUNCTIONS EXPLAINED:
 * 
 *    socket(): Creates a communication endpoint
 *    - Returns a file descriptor (integer) that represents the socket
 *    - Like opening a file, but for network communication
 * 
 *    bind(): Associates socket with an address (IP + port)
 *    - Tells the system "this socket should listen on this address"
 * 
 *    listen(): Marks socket as passive (accepting connections)
 *    - Socket is now ready to accept incoming connections
 * 
 *    accept(): Accepts an incoming connection
 *    - Blocks until a client connects
 *    - Returns a new file descriptor for the client
 * 
 *    poll(): Waits for activity on multiple file descriptors
 *    - More efficient than checking each socket individually
 *    - Tells us when sockets have data to read or are ready to write
 * 
 *    recv()/send(): Read/write data from/to sockets
 *    - Like read()/write() but for network sockets
 * 
 *    close(): Closes a file descriptor
 *    - Frees up the socket for reuse
 * 
 * 7. MEMORY MANAGEMENT:
 *    - Always pair new with delete
 *    - Check for NULL pointers before using them
 *    - Use RAII (Resource Acquisition Is Initialization) when possible
 *    - Destructors automatically clean up when objects are destroyed
 */
