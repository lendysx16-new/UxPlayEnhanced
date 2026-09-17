from pathlib import Path

ROOT = Path(__file__).resolve().parent
TARGET = ROOT / "lib" / "uxplay" / "lib" / "dnssd_embedded.c"

text = TARGET.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    '''/** Send a packet to the mDNS multicast group. */
static void mdns_send(int sock, const uint8_t *pkt, int pkt_len)
{
    struct sockaddr_in dest;
    memset(&dest, 0, sizeof(dest));
    dest.sin_family = AF_INET;
    dest.sin_port = htons(MDNS_PORT);
    dest.sin_addr.s_addr = inet_addr(MDNS_ADDR);
    sendto(sock, (const char *)pkt, pkt_len, 0,
           (struct sockaddr *)&dest, sizeof(dest));
}
''',
    '''/** Send a packet to the mDNS multicast group, with transport diagnostics. */
static int mdns_send(int sock, const uint8_t *pkt, int pkt_len)
{
    struct sockaddr_in dest;
    memset(&dest, 0, sizeof(dest));
    dest.sin_family = AF_INET;
    dest.sin_port = htons(MDNS_PORT);
    dest.sin_addr.s_addr = inet_addr(MDNS_ADDR);

    int sent = sendto(sock, (const char *)pkt, pkt_len, 0,
                      (struct sockaddr *)&dest, sizeof(dest));
#ifdef WIN32
    if (sent == SOCKET_ERROR) {
        fprintf(stderr,
                "embedded mDNS DEBUG: sendto dst=%s:%d bytes=%d FAILED WSA=%d\\n",
                MDNS_ADDR, MDNS_PORT, pkt_len, WSAGetLastError());
    } else {
        fprintf(stdout,
                "embedded mDNS DEBUG: sendto dst=%s:%d bytes=%d sent=%d\\n",
                MDNS_ADDR, MDNS_PORT, pkt_len, sent);
    }
#else
    if (sent < 0) {
        fprintf(stderr,
                "embedded mDNS DEBUG: sendto dst=%s:%d bytes=%d FAILED\\n",
                MDNS_ADDR, MDNS_PORT, pkt_len);
    } else {
        fprintf(stdout,
                "embedded mDNS DEBUG: sendto dst=%s:%d bytes=%d sent=%d\\n",
                MDNS_ADDR, MDNS_PORT, pkt_len, sent);
    }
#endif
    fflush(stdout);
    fflush(stderr);
    return sent;
}
''',
    "mdns_send",
)

replace_once(
    '''        setsockopt(dnssd->mdns_sock, IPPROTO_IP, IP_MULTICAST_IF,
                   (const char *)&dnssd->ifaces[i], sizeof(uint32_t));
        mdns_send(dnssd->mdns_sock, pkt, len);
''',
    '''        struct in_addr iface_addr;
        iface_addr.s_addr = dnssd->ifaces[i];
        int if_result = setsockopt(dnssd->mdns_sock, IPPROTO_IP, IP_MULTICAST_IF,
                                   (const char *)&dnssd->ifaces[i], sizeof(uint32_t));
        if (if_result != 0) {
#ifdef WIN32
            fprintf(stderr,
                    "embedded mDNS DEBUG: IP_MULTICAST_IF iface=%s FAILED WSA=%d\\n",
                    inet_ntoa(iface_addr), WSAGetLastError());
#else
            fprintf(stderr,
                    "embedded mDNS DEBUG: IP_MULTICAST_IF iface=%s FAILED\\n",
                    inet_ntoa(iface_addr));
#endif
            fflush(stderr);
            continue;
        }
        fprintf(stdout,
                "embedded mDNS DEBUG: TX iface=%s dst=%s:%d bytes=%d\\n",
                inet_ntoa(iface_addr), MDNS_ADDR, MDNS_PORT, len);
        fflush(stdout);
        mdns_send(dnssd->mdns_sock, pkt, len);
''',
    "IP_MULTICAST_IF send path",
)

replace_once(
    '''        if (n > 0) {
            process_mdns_packet(dnssd, buf, n);
        }
''',
    '''        if (n > 0) {
            if (n >= 4 && !(read_u16(buf + 2) & 0x8000)) {
                fprintf(stdout,
                        "embedded mDNS DEBUG: RX query bytes=%d from=%s:%u\\n",
                        n, inet_ntoa(from.sin_addr), (unsigned int)ntohs(from.sin_port));
                fflush(stdout);
            }
            process_mdns_packet(dnssd, buf, n);
        }
''',
    "recvfrom query path",
)

TARGET.write_text(text, encoding="utf-8")
print(f"Patched mDNS diagnostics into {TARGET}")
