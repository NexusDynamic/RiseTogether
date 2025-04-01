// Simple sender
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

int main() {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    
    // Set TTL
    int ttl = 2;
    setsockopt(sock, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof(ttl));
    
    // Set outgoing interface
    struct in_addr localInterface;
    localInterface.s_addr = inet_addr("10.77.10.103");  // Your IP
    setsockopt(sock, IPPROTO_IP, IP_MULTICAST_IF, &localInterface, sizeof(localInterface));
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = inet_addr("239.255.255.250");  // Use your multicast IP
    addr.sin_port = htons(5000);  // Use your port
    
    char *message = "Hello, Multicast";
    while (1) {
        sendto(sock, message, strlen(message), 0, 
               (struct sockaddr*)&addr, sizeof(addr));
        printf("Sent message\n");
        sleep(1);
    }
    
    return 0;
}
