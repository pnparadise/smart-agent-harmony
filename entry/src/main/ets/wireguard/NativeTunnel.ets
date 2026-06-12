import wgNative, { NativeTunnelStats } from 'libwg_boringtun.so';
import { WireGuardConfig } from './WireGuardConfig';

export interface TunnelStats {
  running: boolean;
  txBytes: number;
  rxBytes: number;
  latestHandshakeSeconds: number;
  latestPacketSentSeconds: number;
  loss: number;
  rttMillis: number;
}

export class NativeTunnel {
  static create(config: WireGuardConfig, endpointHost?: string): number {
    return wgNative.createTunnel(
      config.iface.privateKey,
      config.peer.publicKey,
      config.peer.presharedKey,
      endpointHost ?? config.peer.endpointHost,
      config.peer.endpointPort,
      config.peer.persistentKeepalive,
      config.iface.mtu
    );
  }

  static getSocketFd(handle: number): number {
    return wgNative.getTunnelSocketFd(handle);
  }

  static start(handle: number, tunFd: number): void {
    wgNative.startTunnel(handle, tunFd);
  }

  static stop(handle: number): void {
    wgNative.stopTunnel(handle);
  }

  static forceHandshake(handle: number): void {
    wgNative.forceTunnelHandshake(handle);
  }

  static stats(handle: number): TunnelStats {
    const stats: NativeTunnelStats = wgNative.getTunnelStats(handle);
    const tunnelStats: TunnelStats = {
      running: stats.running,
      txBytes: NativeTunnel.numberValue(stats.tx_bytes, stats.txBytes, 0),
      rxBytes: NativeTunnel.numberValue(stats.rx_bytes, stats.rxBytes, 0),
      latestHandshakeSeconds: NativeTunnel.numberValue(
        stats.latest_handshake_seconds,
        stats.latestHandshakeSeconds,
        -1
      ),
      latestPacketSentSeconds: NativeTunnel.numberValue(
        stats.latest_packet_sent_seconds,
        stats.latestPacketSentSeconds,
        -1
      ),
      loss: NativeTunnel.numberValue(stats.loss, undefined, 0),
      rttMillis: NativeTunnel.numberValue(stats.rtt_millis, stats.rttMillis, -1)
    };
    return tunnelStats;
  }

  private static numberValue(primary: number | undefined, secondary: number | undefined, fallback: number): number {
    if (primary !== undefined && !Number.isNaN(primary)) {
      return primary;
    }
    if (secondary !== undefined && !Number.isNaN(secondary)) {
      return secondary;
    }
    return fallback;
  }
}
