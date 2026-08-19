import { BusinessError } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';

export interface VpnNetworkMonitorCallbacks {
  onAvailable: (netHandle: connection.NetHandle) => void;
  onLost: (netHandle: connection.NetHandle) => void;
  onError: (operation: string, error: BusinessError) => void;
}

export class VpnNetworkMonitor {
  private observer?: connection.NetConnection;

  start(callbacks: VpnNetworkMonitorCallbacks): void {
    if (this.observer !== undefined) {
      return;
    }
    try {
      const specifier: connection.NetSpecifier = {
        netCapabilities: {
          bearerTypes: [connection.NetBearType.BEARER_VPN]
        }
      };
      const observer = connection.createNetConnection(specifier);
      observer.on('netAvailable', callbacks.onAvailable);
      observer.on('netLost', callbacks.onLost);
      this.observer = observer;
      observer.register((err: BusinessError) => {
        if (err !== undefined && err.code !== 0) {
          if (this.observer === observer) {
            this.observer = undefined;
          }
          callbacks.onError('register', err);
        }
      });
    } catch (err) {
      this.observer = undefined;
      callbacks.onError('start', err as BusinessError);
    }
  }

  stop(onError: (operation: string, error: BusinessError) => void): void {
    const observer = this.observer;
    if (observer === undefined) {
      return;
    }
    this.observer = undefined;
    try {
      observer.unregister((err: BusinessError) => {
        if (err !== undefined && err.code !== 0) {
          onError('unregister', err);
        }
      });
    } catch (err) {
      onError('stop', err as BusinessError);
    }
  }
}

export function queryVpnNetworkAvailable(): boolean | undefined {
  try {
    const netHandles: connection.NetHandle[] = connection.getAllNetsSync();
    for (let index = 0; index < netHandles.length; index++) {
      const capabilities = connection.getNetCapabilitiesSync(netHandles[index]);
      const bearerTypes: connection.NetBearType[] = capabilities.bearerTypes;
      if (bearerTypes.includes(connection.NetBearType.BEARER_VPN)) {
        return true;
      }
    }
    return false;
  } catch (err) {
    return undefined;
  }
}
