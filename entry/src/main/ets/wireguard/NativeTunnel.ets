import wgNative, { NativeTunnelStats } from 'libwg_boringtun.so';
import { WireGuardConfig } from './WireGuardConfig';

export interface TunnelStats {
  running: boolean;
  tunWorkerAlive: boolean;
  udpWorkerAlive: boolean;
  workerExitCode: number;
  lastError: string;
  lastEvent: string;
  lastWorker: string;
  lastErrorAtSeconds: number;
  lastTickSeconds: number;
  txBytes: number;
  rxBytes: number;
  latestHandshakeSeconds: number;
  latestPacketSentSeconds: number;
  loss: number;
  rttMillis: number;
  tunReadPackets: number;
  tunDroppedPackets: number;
  udpReadPackets: number;
  tunWritePackets: number;
  tunReadLast: string;
  tunWriteLast: string;
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

  static tickCount(): number {
    return wgNative.getTickCount();
  }

  static tunnelTickCount(handle: number): number {
    return wgNative.getTunnelTickCount(handle);
  }

  static persistentKeepaliveSeconds(handle: number): number {
    return wgNative.getPersistentKeepaliveSeconds(handle);
  }

  static stats(handle: number): TunnelStats {
    const stats: NativeTunnelStats = wgNative.getTunnelStats(handle);
    const tunnelStats: TunnelStats = {
      running: stats.running,
      tunWorkerAlive: NativeTunnel.booleanValue(stats.tun_worker_alive, stats.tunWorkerAlive, false),
      udpWorkerAlive: NativeTunnel.booleanValue(stats.udp_worker_alive, stats.udpWorkerAlive, false),
      workerExitCode: NativeTunnel.numberValue(stats.worker_exit_code, stats.workerExitCode, 0),
      lastError: NativeTunnel.stringValue(stats.last_error, stats.lastError, ''),
      lastEvent: NativeTunnel.stringValue(stats.last_event, stats.lastEvent, ''),
      lastWorker: NativeTunnel.stringValue(stats.last_worker, stats.lastWorker, ''),
      lastErrorAtSeconds: NativeTunnel.numberValue(stats.last_error_at_seconds, stats.lastErrorAtSeconds, -1),
      lastTickSeconds: NativeTunnel.numberValue(stats.last_tick_seconds, stats.lastTickSeconds, -1),
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
      rttMillis: NativeTunnel.numberValue(stats.rtt_millis, stats.rttMillis, -1),
      tunReadPackets: NativeTunnel.numberValue(stats.tun_read_packets, stats.tunReadPackets, 0),
      tunDroppedPackets: NativeTunnel.numberValue(stats.tun_dropped_packets, stats.tunDroppedPackets, 0),
      udpReadPackets: NativeTunnel.numberValue(stats.udp_read_packets, stats.udpReadPackets, 0),
      tunWritePackets: NativeTunnel.numberValue(stats.tun_write_packets, stats.tunWritePackets, 0),
      tunReadLast: NativeTunnel.stringValue(stats.tun_read_last, stats.tunReadLast, ''),
      tunWriteLast: NativeTunnel.stringValue(stats.tun_write_last, stats.tunWriteLast, '')
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

  private static stringValue(primary: string | undefined, secondary: string | undefined, fallback: string): string {
    if (primary !== undefined && primary.length > 0) {
      return primary;
    }
    if (secondary !== undefined && secondary.length > 0) {
      return secondary;
    }
    return fallback;
  }

  private static booleanValue(primary: boolean | undefined, secondary: boolean | undefined, fallback: boolean): boolean {
    if (primary !== undefined) {
      return primary;
    }
    if (secondary !== undefined) {
      return secondary;
    }
    return fallback;
  }
}
