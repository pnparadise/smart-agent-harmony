export interface NativeTunnelStats {
  running: boolean;
  tx_bytes: number;
  rx_bytes: number;
  latest_handshake_seconds: number;
  latest_packet_sent_seconds: number;
  loss: number;
  rtt_millis: number;
  tun_read_packets: number;
  tun_dropped_packets: number;
  udp_read_packets: number;
  tun_write_packets: number;
  tun_read_last: string;
  tun_write_last: string;
}

export const createTunnel: (
  privateKey: string,
  peerPublicKey: string,
  presharedKey: string,
  endpointHost: string,
  endpointPort: number,
  persistentKeepalive: number,
  mtu: number
) => number;

export const getTunnelSocketFd: (handle: number) => number;

export const startTunnel: (handle: number, tunFd: number) => void;

export const stopTunnel: (handle: number) => void;

export const getTunnelStats: (handle: number) => NativeTunnelStats;

export const getTickCount: () => number;

export const getTunnelTickCount: (handle: number) => number;

export const getPersistentKeepaliveSeconds: (handle: number) => number;

export const forceTunnelHandshake: (handle: number) => void;
