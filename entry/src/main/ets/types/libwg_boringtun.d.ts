declare module 'libwg_boringtun.so' {
  export interface NativeTunnelStats {
    running: boolean;
    tx_bytes?: number;
    rx_bytes?: number;
    latest_handshake_seconds?: number;
    latest_packet_sent_seconds?: number;
    rtt_millis?: number;
    txBytes?: number;
    rxBytes?: number;
    latestHandshakeSeconds?: number;
    latestPacketSentSeconds?: number;
    rttMillis?: number;
    loss?: number;
  }

  export function createTunnel(
    privateKey: string,
    peerPublicKey: string,
    presharedKey: string,
    endpointHost: string,
    endpointPort: number,
    persistentKeepalive: number,
    mtu: number
  ): number;

  export function getTunnelSocketFd(handle: number): number;

  export function startTunnel(handle: number, tunFd: number): void;

  export function stopTunnel(handle: number): void;

  export function getTunnelStats(handle: number): NativeTunnelStats;

  export function forceTunnelHandshake(handle: number): void;

  const wgNative: {
    createTunnel: typeof createTunnel,
    getTunnelSocketFd: typeof getTunnelSocketFd,
    startTunnel: typeof startTunnel,
    stopTunnel: typeof stopTunnel,
    getTunnelStats: typeof getTunnelStats,
    forceTunnelHandshake: typeof forceTunnelHandshake
  };

  export default wgNative;
}
