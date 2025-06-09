#ifndef IRCSERV_HPP
#define IRCSERV_HPP

// Standard C++ includes
#include <iostream>     // For input/output operations (std::cout, std::cerr, etc.)
#include <string>       // For std::string class
#include <vector>       // For std::vector container (dynamic arrays)
#include <map>          // For std::map container (key-value pairs)
#include <sstream>      // For string stream operations
#include <algorithm>    // For standard algorithms like std::find

// C includes (we use C++ versions when possible)
#include <cstring>      // For string manipulation functions
#include <cstdlib>      // For general utilities like atoi()
#include <cerrno>       // For error number definitions

// System includes for networking
#include <sys/socket.h>  // For socket operations
#include <netinet/in.h>  // For internet address family
#include <arpa/inet.h>   // For internet operations
#include <sys/poll.h>    // For poll() function
#include <fcntl.h>       // For file control operations
#include <unistd.h>      // For POSIX operating system API
#include <signal.h>      // For signal handling

// Forward declarations (telling compiler these classes exist)
class Server;
class Client;
class Channel;
class Parser;

#endif
