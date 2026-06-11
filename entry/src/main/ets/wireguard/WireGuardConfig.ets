const SECTION_INTERFACE = 'interface';
const SECTION_PEER = 'peer';
const IPV4_FAMILY = 1;
const IPV6_FAMILY = 2;
export const DEFAULT_PERSISTENT_KEEPALIVE = 25;

export interface WireGuardInterfaceConfig {
  privateKey: string;
  addresses: string[];
  dns: string[];
  mtu: number;
}

export interface WireGuardPeerConfig {
  publicKey: string;
  presharedKey: string;
  endpointHost: string;
  endpointPort: number;
  allowedIPs: string[];
  persistentKeepalive: number;
}

export interface WireGuardConfig {
  iface: WireGuardInterfaceConfig;
  peer: WireGuardPeerConfig;
}

export interface ParsedCidr {
  address: string;
  prefixLength: number;
  family: number;
}

interface Endpoint {
  host: string;
  port: number;
}

export const DEFAULT_WG_CONFIG: string =
  '[Interface]\n' +
  'PrivateKey = REPLACE_WITH_CLIENT_PRIVATE_KEY\n' +
  'Address = 10.7.0.2/32\n' +
  'DNS = 1.1.1.1, 8.8.8.8\n' +
  'MTU = 1280\n' +
  '\n' +
  '[Peer]\n' +
  'PublicKey = REPLACE_WITH_SERVER_PUBLIC_KEY\n' +
  'PresharedKey = \n' +
  'AllowedIPs = 0.0.0.0/0\n' +
  'Endpoint = 203.0.113.10:51820\n' +
  'PersistentKeepalive = ' + String(DEFAULT_PERSISTENT_KEEPALIVE) + '\n';

export function parseWireGuardConfig(text: string): WireGuardConfig {
  const iface = new Map<string, string>();
  const peer = new Map<string, string>();
  let section = '';

  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const raw = stripComment(lines[i]).trim();
    if (raw.length === 0) {
      continue;
    }

    if (raw.startsWith('[') && raw.endsWith(']')) {
      section = raw.substring(1, raw.length - 1).trim().toLowerCase();
      continue;
    }

    const equalsIndex = raw.indexOf('=');
    if (equalsIndex < 0) {
      throw new Error('Invalid WireGuard line ' + (i + 1).toString());
    }

    const key = normalizeKey(raw.substring(0, equalsIndex));
    const value = raw.substring(equalsIndex + 1).trim();
    if (section === SECTION_INTERFACE) {
      iface.set(key, value);
    } else if (section === SECTION_PEER) {
      peer.set(key, value);
    } else {
      throw new Error('Line outside [Interface] or [Peer] at ' + (i + 1).toString());
    }
  }

  const endpoint = parseEndpoint(required(peer, 'endpoint'));
  const mtuValue = optionalNumber(iface.get('mtu'), 1280);
  const keepaliveValue = optionalNumber(peer.get('persistentkeepalive'), DEFAULT_PERSISTENT_KEEPALIVE);
  if (mtuValue < 576 || mtuValue > 1500) {
    throw new Error('MTU must be between 576 and 1500');
  }
  if (keepaliveValue < 0 || keepaliveValue > 65535) {
    throw new Error('PersistentKeepalive must be between 0 and 65535');
  }

  return {
    iface: {
      privateKey: required(iface, 'privatekey'),
      addresses: splitCsv(required(iface, 'address')),
      dns: splitCsv(iface.get('dns') ?? ''),
      mtu: mtuValue
    },
    peer: {
      publicKey: required(peer, 'publickey'),
      presharedKey: peer.get('presharedkey') ?? '',
      endpointHost: endpoint.host,
      endpointPort: endpoint.port,
      allowedIPs: splitCsv(required(peer, 'allowedips')),
      persistentKeepalive: keepaliveValue
    }
  };
}

export function parseCidr(cidr: string): ParsedCidr {
  const parts = cidr.trim().split('/');
  if (parts.length === 0 || parts[0].trim().length === 0) {
    throw new Error('Invalid CIDR: ' + cidr);
  }

  const address = parts[0].trim();
  const family = address.indexOf(':') >= 0 ? IPV6_FAMILY : IPV4_FAMILY;
  const defaultPrefix = family === IPV6_FAMILY ? 128 : 32;
  const prefixLength = parts.length > 1 ? Number(parts[1].trim()) : defaultPrefix;
  if (Number.isNaN(prefixLength) || prefixLength < 0 || prefixLength > defaultPrefix) {
    throw new Error('Invalid prefix length: ' + cidr);
  }

  return {
    address,
    prefixLength,
    family
  };
}

export function hasIPv4(config: WireGuardConfig): boolean {
  return config.iface.addresses.some((value: string) => parseCidr(value).family === IPV4_FAMILY);
}

export function hasIPv6(config: WireGuardConfig): boolean {
  return config.iface.addresses.some((value: string) => parseCidr(value).family === IPV6_FAMILY);
}

function stripComment(line: string): string {
  const index = line.indexOf('#');
  if (index < 0) {
    return line;
  }
  return line.substring(0, index);
}

function normalizeKey(key: string): string {
  return key.trim().toLowerCase().replace(/\s+/g, '');
}

function required(values: Map<string, string>, key: string): string {
  const value = values.get(key);
  if (value === undefined || value.trim().length === 0) {
    throw new Error('Missing WireGuard field: ' + key);
  }
  return value.trim();
}

function splitCsv(value: string): string[] {
  if (value.trim().length === 0) {
    return [];
  }
  return value
    .split(',')
    .map((item: string) => item.trim())
    .filter((item: string) => item.length > 0);
}

function optionalNumber(value: string | undefined, fallback: number): number {
  if (value === undefined || value.trim().length === 0) {
    return fallback;
  }
  const parsed = Number(value.trim());
  if (Number.isNaN(parsed)) {
    return fallback;
  }
  return parsed;
}

function parseEndpoint(value: string): Endpoint {
  const trimmed = value.trim();
  let host = '';
  let portText = '';

  if (trimmed.startsWith('[')) {
    const end = trimmed.indexOf(']');
    if (end < 0 || trimmed.length <= end + 2 || trimmed.charAt(end + 1) !== ':') {
      throw new Error('Invalid IPv6 endpoint');
    }
    host = trimmed.substring(1, end);
    portText = trimmed.substring(end + 2);
  } else {
    const index = trimmed.lastIndexOf(':');
    if (index <= 0) {
      throw new Error('Invalid endpoint');
    }
    host = trimmed.substring(0, index);
    portText = trimmed.substring(index + 1);
  }

  const port = Number(portText);
  if (host.length === 0 || Number.isNaN(port) || port <= 0 || port > 65535) {
    throw new Error('Invalid endpoint');
  }

  const endpoint: Endpoint = {
    host: host,
    port: port
  };
  return endpoint;
}
